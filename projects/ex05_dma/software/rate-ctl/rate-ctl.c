/* rate-ctl -- program and read back the per-channel axi_rate_gen pacers.
 *
 * ex05 puts an axi_rate_gen between each channel's DAC and ADC FIFO (the SPI
 * core's role in rev_d_shim). Each pacer throttles its DAC->ADC stream to a
 * programmed rate and can pause it. Control and status are one 32-bit word per
 * channel in a shared cfg/sts register pair, reached the same non-root way as
 * ex03: two pl-reg device nodes, mmap'd once, then plain load/store.
 *
 *   /dev/rate_cfg   writable, word[ch] = control (rate_div + pause)
 *   /dev/rate_sts   read-only, word[ch] = BEAT_COUNT forwarded since reset
 *
 * Both nodes come up mode 0666 (set by pl-reg, no udev rule), so this runs as
 * an ordinary user -- no sudo, no hardcoded addresses. The names are the Vivado
 * instance names PetaLinux preserves in the device tree.
 *
 * Register layout (mirror axi_rate_gen.v):
 *   cfg[ch][15:0]  RATE_DIV   extra idle cycles between beats
 *                             (0 = full rate, N = one beat every N+1 cycles)
 *   cfg[ch][16]    PAUSE      freeze this channel's stream while set
 *   sts[ch][31:0]  BEAT_COUNT saturating count of beats forwarded since reset
 *
 * Typical use: program per-channel rates, run `mcdma-loopback` in another shell
 * to push traffic through, then read the beat counts back here to see each
 * channel advancing at its own rate.
 *
 * Usage:
 *   rate-ctl                       show every channel's rate/pause and count
 *   rate-ctl set <ch> <div> [p]    set channel <ch> to RATE_DIV=<div>, PAUSE=p
 *   rate-ctl all <div> [p]         set every channel the same
 *   rate-ctl pause <ch>            pause channel <ch>
 *   rate-ctl run <ch>              unpause channel <ch> (keep its rate)
 * (p is 0 or 1 and defaults to 0.)
 */

#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define CFG_PATH   "/dev/rate_cfg"
#define STS_PATH   "/dev/rate_sts"

#define MAP_SIZE   0x1000UL   /* one page covers the small register window */

/* Number of channels -- must match `set num_ch` in block_design.tcl. */
#define NUM_CH     8

#define RATE_DIV_MASK  0xFFFFu
#define PAUSE_BIT      (1u << 16)

static volatile uint32_t *open_and_map(const char *path, int prot, int *fd_out)
{
  int flags = (prot & PROT_WRITE) ? O_RDWR : O_RDONLY;
  int fd = open(path, flags);
  if (fd < 0) {
    fprintf(stderr, "Failed to open %s: %s\n", path, strerror(errno));
    if (errno == ENOENT)
      fprintf(stderr, "  Is pl-reg loaded and bound? Try: dmesg | grep pl-reg\n");
    else if (errno == EACCES)
      fprintf(stderr, "  Permission denied on %s (no sudo should be needed).\n", path);
    return NULL;
  }

  void *p = mmap(NULL, MAP_SIZE, prot, MAP_SHARED, fd, 0);
  if (p == MAP_FAILED) {
    fprintf(stderr, "mmap of %s failed: %s\n", path, strerror(errno));
    close(fd);
    return NULL;
  }

  *fd_out = fd;
  return (volatile uint32_t *)p;
}

static void set_channel(volatile uint32_t *cfg, int ch, unsigned rate_div, int pause)
{
  uint32_t word = (rate_div & RATE_DIV_MASK) | (pause ? PAUSE_BIT : 0u);
  cfg[ch] = word;
}

static void print_status(volatile uint32_t *cfg, volatile uint32_t *sts)
{
  printf("  ch   rate_div  pause   beat_count\n");
  for (int ch = 0; ch < NUM_CH; ch++) {
    uint32_t c = cfg[ch];
    printf("  %2d   %8u    %d     %10" PRIu32 "\n",
           ch, c & RATE_DIV_MASK, (c & PAUSE_BIT) ? 1 : 0, sts[ch]);
  }
}

static int parse_ch(const char *s, int *ch)
{
  char *end;
  long v = strtol(s, &end, 0);
  if (*end != '\0' || v < 0 || v >= NUM_CH) {
    fprintf(stderr, "Bad channel '%s' (expected 0..%d)\n", s, NUM_CH - 1);
    return -1;
  }
  *ch = (int)v;
  return 0;
}

int main(int argc, char **argv)
{
  int cfg_fd = -1, sts_fd = -1, rc = EXIT_FAILURE;
  volatile uint32_t *cfg = open_and_map(CFG_PATH, PROT_READ | PROT_WRITE, &cfg_fd);
  volatile uint32_t *sts = open_and_map(STS_PATH, PROT_READ, &sts_fd);
  if (!cfg || !sts)
    goto out;

  if (argc == 1) {
    printf("rate-ctl: %d channels via %s + %s (no root)\n\n", NUM_CH, CFG_PATH, STS_PATH);
    print_status(cfg, sts);
    rc = EXIT_SUCCESS;
    goto out;
  }

  if (strcmp(argv[1], "set") == 0 && (argc == 4 || argc == 5)) {
    int ch;
    if (parse_ch(argv[2], &ch) < 0) goto out;
    unsigned div = (unsigned)strtoul(argv[3], NULL, 0);
    int pause = (argc == 5) ? (atoi(argv[4]) != 0) : 0;
    set_channel(cfg, ch, div, pause);
    printf("ch%d: rate_div=%u pause=%d\n", ch, div & RATE_DIV_MASK, pause);
    rc = EXIT_SUCCESS;
  } else if (strcmp(argv[1], "all") == 0 && (argc == 3 || argc == 4)) {
    unsigned div = (unsigned)strtoul(argv[2], NULL, 0);
    int pause = (argc == 4) ? (atoi(argv[3]) != 0) : 0;
    for (int ch = 0; ch < NUM_CH; ch++)
      set_channel(cfg, ch, div, pause);
    printf("all channels: rate_div=%u pause=%d\n", div & RATE_DIV_MASK, pause);
    rc = EXIT_SUCCESS;
  } else if (strcmp(argv[1], "pause") == 0 && argc == 3) {
    int ch;
    if (parse_ch(argv[2], &ch) < 0) goto out;
    cfg[ch] = cfg[ch] | PAUSE_BIT;
    printf("ch%d: paused\n", ch);
    rc = EXIT_SUCCESS;
  } else if (strcmp(argv[1], "run") == 0 && argc == 3) {
    int ch;
    if (parse_ch(argv[2], &ch) < 0) goto out;
    cfg[ch] = cfg[ch] & ~PAUSE_BIT;
    printf("ch%d: running\n", ch);
    rc = EXIT_SUCCESS;
  } else {
    fprintf(stderr,
            "Usage:\n"
            "  %s                     show all channels\n"
            "  %s set <ch> <div> [p]  set RATE_DIV=<div>, PAUSE=p (0/1)\n"
            "  %s all <div> [p]       set every channel the same\n"
            "  %s pause <ch>          pause a channel\n"
            "  %s run <ch>            unpause a channel\n",
            argv[0], argv[0], argv[0], argv[0], argv[0]);
  }

out:
  if (cfg) munmap((void *)cfg, MAP_SIZE);
  if (sts) munmap((void *)sts, MAP_SIZE);
  if (cfg_fd >= 0) close(cfg_fd);
  if (sts_fd >= 0) close(sts_fd);
  return rc;
}
