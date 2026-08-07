/* reg-mem -- baseline register access through /dev/mem
 *
 * This is the "before" case for ex05. It reaches the PL exactly the way the
 * Rev D Shim software does today: open /dev/mem, mmap the physical address of
 * each AXI register, and dereference the result. Compare it with reg-driver.c,
 * which reaches the SAME registers through the pl-reg driver -- by name, no
 * root, no hardcoded addresses.
 *
 * Two things are worth noticing while running it:
 *
 *   1. It needs root. /dev/mem is a window onto ALL of physical memory, so
 *      handing it out is handing out the whole machine. There is no way to
 *      grant a user access to just the shim registers through this interface.
 *
 *   2. Nothing here knows what the registers mean. The base addresses below
 *      are copied by hand from block_design.tcl, and nothing checks that they
 *      still match. Move a peripheral in the block design and this file keeps
 *      compiling, keeps running, and quietly reads the wrong memory.
 *
 *
 * Run with:  sudo reg-mem
 */

#define _POSIX_C_SOURCE 199309L  /* clock_gettime, CLOCK_MONOTONIC */

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

/* Addresses are defined in the hardware design Tcl file. Keeping them in sync
 * is entirely manual -- see the note at the top of this file. */
#define CFG_BASE       0x40000000UL
#define STS_BASE       0x40100000UL

#define MAP_SIZE       0x1000UL   /* one page per register block */

#define BENCH_ITERS    100000

/* 32-bit word offsets within the 64-bit CFG register */
#define CFG_WORD_A     0
#define CFG_WORD_B     1

static volatile uint32_t *map_region(int fd, unsigned long base, const char *name)
{
  void *p = mmap(NULL, MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, base);
  if (p == MAP_FAILED) {
    fprintf(stderr, "mmap of %s at 0x%08lx failed: %s\n", name, base, strerror(errno));
    return NULL;
  }
  return (volatile uint32_t *)p;
}

/* Write two words into CFG and check that STS returns their bitwise NAND.
 * Returns 0 on success, or the number of mismatches. */
static int check_nand(volatile uint32_t *cfg, volatile uint32_t *sts, const char *label)
{
  static const uint32_t vectors[][2] = {
    {0x00000000, 0x00000000},
    {0xffffffff, 0xffffffff},
    {0xaaaaaaaa, 0x55555555},
    {0xdeadbeef, 0xffffffff},
    {0x0f0f0f0f, 0xf0f0f0f0},
    {0x12345678, 0x87654321},
  };
  const int n = sizeof(vectors) / sizeof(vectors[0]);
  int failures = 0;

  printf("  %s: PL round trip\n", label);
  for (int i = 0; i < n; i++) {
    uint32_t a = vectors[i][0];
    uint32_t b = vectors[i][1];
    uint32_t expect = ~(a & b);

    cfg[CFG_WORD_A] = a;
    cfg[CFG_WORD_B] = b;
    uint32_t got = sts[0];

    int ok = (got == expect);
    if (!ok) failures++;
    printf("    %s  nand(0x%08" PRIx32 ", 0x%08" PRIx32 ") = 0x%08" PRIx32
           "  expected 0x%08" PRIx32 "\n",
           ok ? "ok  " : "FAIL", a, b, got, expect);
  }
  return failures;
}

/* Time a tight loop of register writes, to give the driver-based programs
 * something concrete to be compared against. */
static void benchmark(volatile uint32_t *cfg)
{
  struct timespec t0, t1;

  /* Warm the mapping so we are not timing a first-touch page fault. */
  cfg[CFG_WORD_A] = 0;

  clock_gettime(CLOCK_MONOTONIC, &t0);
  for (int i = 0; i < BENCH_ITERS; i++)
    cfg[CFG_WORD_A] = (uint32_t)i;
  clock_gettime(CLOCK_MONOTONIC, &t1);

  double elapsed_ns = (double)(t1.tv_sec - t0.tv_sec) * 1e9
                    + (double)(t1.tv_nsec - t0.tv_nsec);

  printf("  %d register writes in %.2f ms  ->  %.1f ns per write\n",
         BENCH_ITERS, elapsed_ns / 1e6, elapsed_ns / BENCH_ITERS);
}

int main(void)
{
  printf("reg-mem: register access via /dev/mem\n\n");

  int fd = open("/dev/mem", O_RDWR | O_SYNC);
  if (fd < 0) {
    fprintf(stderr, "Failed to open /dev/mem: %s\n", strerror(errno));
    if (errno == EACCES)
      fprintf(stderr, "This program needs root. Try: sudo reg-mem\n");
    return EXIT_FAILURE;
  }

  /* This is the same block the pl-reg driver binds to (as /dev/cfg + /dev/sts).
   * Before the driver is loaded, /dev/mem can reach it as shown here (as
   * root). */
  struct {
    const char *label;
    unsigned long cfg_base;
    unsigned long sts_base;
  } blocks[] = {
    { "cfg/sts block", CFG_BASE, STS_BASE },
  };

  int failures = 0;

  for (unsigned i = 0; i < sizeof(blocks) / sizeof(blocks[0]); i++) {
    printf("%s  CFG 0x%08lx  STS 0x%08lx\n",
           blocks[i].label, blocks[i].cfg_base, blocks[i].sts_base);

    volatile uint32_t *cfg = map_region(fd, blocks[i].cfg_base, "CFG");
    volatile uint32_t *sts = map_region(fd, blocks[i].sts_base, "STS");
    if (!cfg || !sts) {
      failures++;
      if (cfg) munmap((void *)cfg, MAP_SIZE);
      if (sts) munmap((void *)sts, MAP_SIZE);
      continue;
    }

    failures += check_nand(cfg, sts, blocks[i].label);
    benchmark(cfg);
    printf("\n");

    munmap((void *)cfg, MAP_SIZE);
    munmap((void *)sts, MAP_SIZE);
  }

  close(fd);

  if (failures) {
    printf("FAILED: %d check(s) did not match\n", failures);
    return EXIT_FAILURE;
  }
  printf("All checks passed.\n");
  return EXIT_SUCCESS;
}
