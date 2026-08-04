/* reg-test -- register access through the simple-reg device driver.
 *
 * This is the "after" case for ex05. Compare it side by side with
 * reg-mem-test.c (the /dev/mem "before" case): the structure is identical --
 * open, mmap, dereference -- and only two lines really differ.
 *
 *   /dev/mem version                        simple-reg version
 *   ----------------                        ------------------
 *   open("/dev/mem", ...)          ->       open("/dev/simple-reg", ...)
 *   mmap(..., fd, 0x40000000)      ->       mmap(..., fd, CFG_REGION * page)
 *   mmap(..., fd, 0x40100000)      ->       mmap(..., fd, STS_REGION * page)
 *   needs root                     ->       runs as an ordinary user
 *
 * What you gain by moving to the driver:
 *
 *   1. No root. /dev/simple-reg comes up mode 0666 (set by the driver itself,
 *      no udev rule), so a normal user can open it. /dev/mem never can, because
 *      it is a window onto all of physical memory.
 *
 *   2. No hardcoded addresses. Userspace names regions ("region 0", "region
 *      1"), not 0x40000000. The device tree tells the driver where the block
 *      really is; if it moves, this program does not change.
 *
 *   3. Same speed. mmap installs page tables straight to the registers, so
 *      after setup every access is a plain load/store -- no syscall per access.
 *      The benchmark below should match reg-mem-test almost exactly.
 *
 * Run with:  reg-test        (no sudo)
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

#define DEV_PATH       "/dev/simple-reg"

/* The driver's mmap ABI: the offset selects a region, one page per region.
 * Region 0 is "cfg", region 1 is "sts" (see simple-reg.c). No physical
 * addresses appear anywhere in this program. */
#define CFG_REGION     0
#define STS_REGION     1

#define MAP_SIZE       0x1000UL   /* one page per register */

#define BENCH_ITERS    100000

/* 32-bit word offsets within the 64-bit CFG register */
#define CFG_WORD_A     0
#define CFG_WORD_B     1

static volatile uint32_t *map_region(int fd, unsigned region, const char *name)
{
  off_t offset = (off_t)region * sysconf(_SC_PAGESIZE);
  void *p = mmap(NULL, MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, offset);
  if (p == MAP_FAILED) {
    fprintf(stderr, "mmap of %s (region %u) failed: %s\n",
            name, region, strerror(errno));
    return NULL;
  }
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

/* Time a tight loop of register writes, to compare against reg-mem-test. */
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
  printf("reg-test: register access via %s (no root)\n\n", DEV_PATH);

  int fd = open(DEV_PATH, O_RDWR);
  if (fd < 0) {
    fprintf(stderr, "Failed to open %s: %s\n", DEV_PATH, strerror(errno));
    if (errno == ENOENT)
      fprintf(stderr, "Is the simple-reg module loaded? Try: modprobe simple-reg\n");
    else if (errno == EACCES)
      fprintf(stderr, "Permission denied -- check the group on %s (no sudo should be needed).\n", DEV_PATH);
    return EXIT_FAILURE;
  }

  volatile uint32_t *cfg = map_region(fd, CFG_REGION, "cfg");
  volatile uint32_t *sts = map_region(fd, STS_REGION, "sts");
  if (!cfg || !sts) {
    if (cfg) munmap((void *)cfg, MAP_SIZE);
    if (sts) munmap((void *)sts, MAP_SIZE);
    close(fd);
    return EXIT_FAILURE;
  }

  int failures = check_nand(cfg, sts);
  benchmark(cfg);
  printf("\n");

  munmap((void *)cfg, MAP_SIZE);
  munmap((void *)sts, MAP_SIZE);
  close(fd);

  if (failures) {
    printf("FAILED: %d check(s) did not match\n", failures);
    return EXIT_FAILURE;
  }
  printf("All checks passed.\n");
  return EXIT_SUCCESS;
}
