/* reg-driver -- register access through the pl-reg device driver.
 *
 * This is the "after" case for ex05. Compare it side by side with reg-mem.c
 * (the /dev/mem "before" case): the structure is identical -- open, mmap,
 * dereference -- and only a couple of lines really differ.
 *
 *   /dev/mem version (reg-mem.c)            pl-reg version (this file)
 *   ----------------------------            --------------------------
 *   open("/dev/mem", ...)          ->       open("/dev/cfg", ...)  + open("/dev/sts", ...)
 *   mmap(..., memfd, 0x40000000)   ->       mmap(..., cfgfd, 0)
 *   mmap(..., memfd, 0x40100000)   ->       mmap(..., stsfd, 0)
 *   needs root                     ->       runs as an ordinary user
 *
 * What you gain by moving to the driver:
 *
 *   1. No root. /dev/cfg and /dev/sts come up mode 0666 (set by the driver
 *      itself, no udev rule), so a normal user can open them. /dev/mem never
 *      can, because it is a window onto all of physical memory.
 *
 *   2. No hardcoded addresses. Userspace opens registers by NAME -- /dev/cfg,
 *      /dev/sts -- not by 0x40000000. Those names are the Vivado instance names,
 *      which PetaLinux preserves in the auto-generated device tree (as labels in
 *      the /__symbols__ node), so there is no hand-written device tree either. If
 *      a block moves in the hardware design, the node moves with it and this
 *      program does not change. If a core's VLNV changes, the driver stops
 *      binding and the open() below fails loudly with ENOENT instead of reading
 *      the wrong reg.
 *
 *   3. Same speed. mmap installs page tables straight to the registers, so
 *      after setup every access is a plain load/store -- no syscall per access.
 *      The benchmark below should match reg-mem almost exactly.
 *
 * Run with:  reg-driver      (no sudo)
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

/* One device node per register window. The names are the Vivado instance names
 * (from the device-tree /__symbols__ labels) that pl-reg turns into /dev
 * entries. No physical addresses appear anywhere in this program. */
#define CFG_PATH       "/dev/cfg"
#define STS_PATH       "/dev/sts"

#define MAP_SIZE       0x1000UL   /* one page per register window */

#define BENCH_ITERS    100000

/* 32-bit word offsets within the 64-bit CFG register */
#define CFG_WORD_A     0
#define CFG_WORD_B     1

/* Open a pl-reg node and mmap its single window (always at offset 0). On
 * success stores the fd in *fd_out and returns the mapping; on failure prints a
 * diagnostic and returns NULL. */
static volatile uint32_t *open_and_map(const char *path, int *fd_out)
{
  int fd = open(path, O_RDWR);
  if (fd < 0) {
    fprintf(stderr, "Failed to open %s: %s\n", path, strerror(errno));
    if (errno == ENOENT)
      fprintf(stderr, "  Is the pl-reg module loaded and bound? Try: dmesg | grep pl-reg\n");
    else if (errno == EACCES)
      fprintf(stderr, "  Permission denied on %s (no sudo should be needed).\n", path);
    return NULL;
  }

  void *p = mmap(NULL, MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (p == MAP_FAILED) {
    fprintf(stderr, "mmap of %s failed: %s\n", path, strerror(errno));
    close(fd);
    return NULL;
  }

  *fd_out = fd;
  return (volatile uint32_t *)p;
}

/* Write two words into CFG and check that STS returns their bitwise NAND. */
static int check_nand(volatile uint32_t *cfg, volatile uint32_t *sts)
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

  printf("  PL round trip\n");
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

/* Time a tight loop of register writes, to compare against reg-mem. */
static void benchmark(volatile uint32_t *cfg)
{
  struct timespec t0, t1;

  cfg[CFG_WORD_A] = 0;  /* warm the mapping */

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
  printf("reg-driver: register access via %s + %s (no root)\n\n",
         CFG_PATH, STS_PATH);

  int cfg_fd = -1, sts_fd = -1;
  volatile uint32_t *cfg = open_and_map(CFG_PATH, &cfg_fd);
  volatile uint32_t *sts = open_and_map(STS_PATH, &sts_fd);
  if (!cfg || !sts) {
    if (cfg) munmap((void *)cfg, MAP_SIZE);
    if (sts) munmap((void *)sts, MAP_SIZE);
    if (cfg_fd >= 0) close(cfg_fd);
    if (sts_fd >= 0) close(sts_fd);
    return EXIT_FAILURE;
  }

  int failures = check_nand(cfg, sts);
  benchmark(cfg);
  printf("\n");

  munmap((void *)cfg, MAP_SIZE);
  munmap((void *)sts, MAP_SIZE);
  close(cfg_fd);
  close(sts_fd);

  if (failures) {
    printf("FAILED: %d check(s) did not match\n", failures);
    return EXIT_FAILURE;
  }
  printf("All checks passed.\n");
  return EXIT_SUCCESS;
}
