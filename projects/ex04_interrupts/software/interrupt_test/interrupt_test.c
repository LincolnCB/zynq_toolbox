/* interrupt_test -- raise PL interrupts and catch them non-root via pl-irq.
 *
 * ex04 wires eight PL interrupt lines to the PS. A CFG register in the fabric
 * (axi_cfg_register, instance "axi_irq") is sliced bit-by-bit into IRQ_F2P, so
 * writing bit n raises fabric interrupt line n. This program writes those bits
 * and blocks until the matching interrupt is delivered to userspace.
 *
 * Everything here is non-root, using the two out-of-tree kernel modules this
 * repo ships (both autoloaded from the project's kernel_modules/):
 *
 *   - pl-reg  maps the CFG register as /dev/axi_irq (mode 0666), so the bits are
 *     driven with a plain mmap and no /dev/mem / sudo. (This is the device the
 *     device-driver example is built around.)
 *
 *   - pl-irq  publishes each interrupt line as a misc device named from its
 *     device-tree label (/dev/user_irq0 .. /dev/user_irq7, mode 0666). It is the
 *     interrupt sibling of pl-reg: open it, write() 1 to arm, poll()/read() to
 *     block until the line fires, then clear the source and write() 1 to re-arm.
 *     Unlike the in-tree generic-uio driver it needs no kernel command line and
 *     no chmod (see the README for that alternative).
 *
 * The whole thing is single-threaded: one poll() waits on stdin AND all eight
 * interrupt file descriptors at once. A command typed at the prompt raises a
 * line; the same poll() then wakes on the resulting interrupt, services it, and
 * prints it. pl-irq masks a line at the GIC the moment it fires, so even a
 * level-triggered line delivers exactly one interrupt per pulse -- the service
 * routine clears the source bit and re-arms for the next one.
 *
 * Run with:  interrupt-test      (no sudo)
 */

#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define NUM_IRQ      8
#define CFG_PATH     "/dev/axi_irq"      /* pl-reg node for the CFG register */
#define IRQ_PATH_FMT "/dev/user_irq%d"   /* pl-irq node per line             */
#define MAP_SIZE     0x1000UL            /* one page covers the 64-bit CFG   */
#define SELFTEST_MS  500                 /* per-line wait in the self-test   */

/* Line n's GIC shared-peripheral-interrupt number and trigger type, matching
 * cfg/.../device_tree.dtsi. Lines 0,1,4,5 are rising-edge; 2,3,6,7 level-high.
 * The SPI shows up as 32 + spi in /proc/interrupts (so 61..68 here). */
static const int spi_of[NUM_IRQ]   = { 29, 30, 31, 32, 33, 34, 35, 36 };
static const int level_of[NUM_IRQ] = {  0,  0,  1,  1,  0,  0,  1,  1 };

static volatile uint32_t *cfg;           /* mmap'd CFG register (two 32-bit words) */
static int      irq_fd[NUM_IRQ];         /* pl-irq file descriptors               */
static unsigned received[NUM_IRQ];       /* interrupts seen per line              */

/* The eight lines come from two 32-bit CFG words: bits 0-3 of word 0 drive lines
 * 0-3, bits 0-3 of word 1 drive lines 4-7 (see block_design.tcl). */
static void cfg_set_bit(int line, int val)
{
	volatile uint32_t *word = &cfg[line < 4 ? 0 : 1];
	uint32_t mask = 1u << (line & 3);

	if (val)
		*word |= mask;
	else
		*word &= ~mask;
}

/* Arm (or re-arm) a pl-irq line: write 1 re-enables the IRQ at the GIC. */
static void irq_arm(int line)
{
	uint32_t one = 1;

	if (write(irq_fd[line], &one, sizeof(one)) != (ssize_t)sizeof(one))
		fprintf(stderr, "  warning: failed to arm line %d: %s\n",
			line, strerror(errno));
}

/* Service one fired line: consume the pl-irq event, count it, drop the source
 * bit so a level line stops asserting, then re-arm for the next pulse. */
static void service(int line)
{
	uint32_t count = 0;

	if (read(irq_fd[line], &count, sizeof(count)) != (ssize_t)sizeof(count))
		return;
	received[line]++;
	cfg_set_bit(line, 0);
	irq_arm(line);
	printf("  [irq] line %d fired  (device count %u, total %u)\n",
	       line, count, received[line]);
}

/* Poll all eight interrupt fds once (not stdin) and service whatever fired.
 * Returns the number of fds serviced, or -1 on poll error. */
static int pump_irqs(int timeout_ms)
{
	struct pollfd pfd[NUM_IRQ];
	int r, n = 0;

	for (int i = 0; i < NUM_IRQ; i++) {
		pfd[i].fd = irq_fd[i];
		pfd[i].events = POLLIN;
		pfd[i].revents = 0;
	}
	r = poll(pfd, NUM_IRQ, timeout_ms);
	if (r < 0)
		return -1;
	for (int i = 0; i < NUM_IRQ; i++) {
		if (pfd[i].revents & POLLIN) {
			service(i);
			n++;
		}
	}
	return n;
}

static long now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

/* Pulse each line once and confirm the interrupt reaches userspace. This is the
 * end-to-end check of the whole path: CFG bit -> IRQ_F2P -> GIC -> pl-irq ->
 * poll()/read(). */
static int self_test(void)
{
	int fails = 0;

	printf("Self-test: pulsing each line and waiting for its interrupt\n");
	printf("  line  spi  proc  trigger  result\n");
	for (int i = 0; i < NUM_IRQ; i++) {
		unsigned before = received[i];
		long deadline;

		cfg_set_bit(i, 1);
		deadline = now_ms() + SELFTEST_MS;
		while (received[i] == before && now_ms() < deadline)
			pump_irqs(50);

		if (received[i] == before) {
			cfg_set_bit(i, 0);   /* make sure the source is low  */
			irq_arm(i);          /* and the line stays armed     */
			fails++;
		}
		printf("  %4d  %3d  %4d  %-7s  %s\n", i, spi_of[i], spi_of[i] + 32,
		       level_of[i] ? "level" : "edge",
		       received[i] > before ? "ok" : "NO INTERRUPT");
	}
	if (fails)
		printf("Self-test: %d of %d lines did not deliver an interrupt\n",
		       fails, NUM_IRQ);
	else
		printf("Self-test: all %d lines delivered\n", NUM_IRQ);
	return fails;
}

static void print_help(void)
{
	printf("\n");
	printf("Commands:\n");
	printf("  set <n>     raise line n (0-7); its interrupt is caught and shown\n");
	printf("  set_all     raise all eight lines\n");
	printf("  status      show how many interrupts each line has delivered\n");
	printf("  test        re-run the self-test\n");
	printf("  help        show this message\n");
	printf("  exit        quit\n");
	printf("\n");
	printf("Lines 0,1,4,5 are edge-triggered; 2,3,6,7 level-triggered. pl-irq masks\n");
	printf("a line when it fires, so each 'set' yields exactly one interrupt.\n");
	printf("Watch the counts here against /proc/interrupts (GIC lines 61-68).\n\n");
}

static void print_status(void)
{
	printf("  line  proc  trigger  delivered\n");
	for (int i = 0; i < NUM_IRQ; i++)
		printf("  %4d  %4d  %-7s  %u\n", i, spi_of[i] + 32,
		       level_of[i] ? "level" : "edge", received[i]);
}

/* Read and act on one command line from stdin. Returns 0 to keep running, 1 to
 * quit. */
static int handle_command(void)
{
	char line[128];
	char *tok;

	if (!fgets(line, sizeof(line), stdin))
		return 1;                    /* EOF -> quit */
	line[strcspn(line, "\n")] = '\0';

	tok = strtok(line, " ");
	if (!tok)
		return 0;

	if (!strcmp(tok, "help")) {
		print_help();
	} else if (!strcmp(tok, "status")) {
		print_status();
	} else if (!strcmp(tok, "test")) {
		self_test();
	} else if (!strcmp(tok, "set_all")) {
		for (int i = 0; i < NUM_IRQ; i++)
			cfg_set_bit(i, 1);
		printf("Raised all lines\n");
	} else if (!strcmp(tok, "set")) {
		char *arg = strtok(NULL, " ");
		char *end;
		long n;

		if (!arg) {
			printf("Usage: set <n>  (0-7)\n");
			return 0;
		}
		n = strtol(arg, &end, 10);
		if (end == arg || n < 0 || n >= NUM_IRQ) {
			printf("Invalid line number: %s\n", arg);
			return 0;
		}
		cfg_set_bit((int)n, 1);
		printf("Raised line %ld\n", n);
	} else if (!strcmp(tok, "exit") || !strcmp(tok, "quit")) {
		return 1;
	} else {
		printf("Unknown command: %s (try 'help')\n", tok);
	}
	return 0;
}

int main(void)
{
	int memfd, quit = 0;

	printf("ex04 interrupt test -- non-root via pl-reg + pl-irq\n\n");

	/* CFG register through pl-reg: mmap the named node, no /dev/mem, no sudo. */
	memfd = open(CFG_PATH, O_RDWR);
	if (memfd < 0) {
		fprintf(stderr, "open %s: %s\n", CFG_PATH, strerror(errno));
		if (errno == ENOENT)
			fprintf(stderr, "  Is pl-reg loaded and bound? Try: dmesg | grep pl-reg\n");
		return EXIT_FAILURE;
	}
	cfg = mmap(NULL, MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, memfd, 0);
	if (cfg == MAP_FAILED) {
		fprintf(stderr, "mmap %s: %s\n", CFG_PATH, strerror(errno));
		close(memfd);
		return EXIT_FAILURE;
	}
	cfg[0] = 0;
	cfg[1] = 0;

	/* One pl-irq device per line; arm each so it can fire. */
	for (int i = 0; i < NUM_IRQ; i++) {
		char path[32];

		snprintf(path, sizeof(path), IRQ_PATH_FMT, i);
		irq_fd[i] = open(path, O_RDWR);
		if (irq_fd[i] < 0) {
			fprintf(stderr, "open %s: %s\n", path, strerror(errno));
			if (errno == ENOENT)
				fprintf(stderr, "  Is pl-irq loaded and bound? Try: dmesg | grep pl-irq\n");
			return EXIT_FAILURE;
		}
		irq_arm(i);
	}

	self_test();
	print_help();

	/* One poll() over stdin (fd 0) and every interrupt fd. Commands raise lines;
	 * the interrupts they cause wake the same poll() and get serviced. */
	while (!quit) {
		struct pollfd pfd[1 + NUM_IRQ];

		printf("> ");
		fflush(stdout);

		pfd[0].fd = STDIN_FILENO;
		pfd[0].events = POLLIN;
		pfd[0].revents = 0;
		for (int i = 0; i < NUM_IRQ; i++) {
			pfd[1 + i].fd = irq_fd[i];
			pfd[1 + i].events = POLLIN;
			pfd[1 + i].revents = 0;
		}

		if (poll(pfd, 1 + NUM_IRQ, -1) < 0) {
			if (errno == EINTR)
				continue;
			perror("poll");
			break;
		}

		for (int i = 0; i < NUM_IRQ; i++)
			if (pfd[1 + i].revents & POLLIN)
				service(i);

		if (pfd[0].revents & POLLIN)
			quit = handle_command();
	}

	for (int i = 0; i < NUM_IRQ; i++) {
		cfg_set_bit(i, 0);
		close(irq_fd[i]);
	}
	munmap((void *)cfg, MAP_SIZE);
	close(memfd);
	printf("Exiting.\n");
	return EXIT_SUCCESS;
}
