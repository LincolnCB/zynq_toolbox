/* fault-inject -- exercise the one data hazard the PS/DMA side of ex07 owns:
 * cache coherency. Companion to mcdma-loopback (the happy-path round trip) and
 * rate-ctl (the per-channel pacers).
 *
 * Scope, deliberately narrow. Buffer under/overflow is *not* a PS concern here.
 * In rev_d_shim the DAC/ADC cores detect under/overflow in the PL and raise it
 * through hw_manager's status word + ps_interrupt (its dac_data_buf_*, adc_data_
 * buf_*, and unexp_*_trig inputs); the PS must never time out on a channel that
 * is merely waiting for a trigger -- a buffered sequence can wait arbitrarily long
 * -- and a duplicate PS-side check would conflict with the cores' own detection.
 * The DMA's only response to a fault or shutdown is halt/reset (see the project
 * README "What's left" step 3). So this tool does one useful thing the PS is
 * actually responsible for:
 *
 *   nosync   Stage the payload the wrong way: flush the descriptors and an
 *            all-zero payload to DDR, then write the real per-channel pattern
 *            into the cached src but skip the sync_for_device that would push it
 *            out. u-dma-buf hands out a cached mapping and the MCDMA reads DDR
 *            directly over the non-coherent HP0 port, so MM2S transfers the stale
 *            zeros and every dst comes back all-zero -- the transfer *completes*
 *            with full length and no CH_ERR, but the data is wrong. Silent
 *            corruption, catchable only by a content check. Flushing the
 *            descriptors keeps the engine running cleanly so the fault is pure
 *            data corruption, not a stale-descriptor engine error (skipping the
 *            descriptor flush too gives nondeterministic engine errors instead).
 *            Expected outcome: every channel `corrupt`.
 *
 *   (no arg) Baseline: full sync. Expected outcome: every channel `ok`.
 *
 * The tool knows what it injected, so it checks each channel's observed class
 * against the expected one and prints PASS/FAIL for the run as a whole.
 *
 * It reuses mcdma-loopback's prebuffered flow and register model (see that file
 * for the MCDMA register map and SG descriptor layout notes). To stay
 * deterministic regardless of any prior rate-ctl state, it clears every
 * axi_rate_gen pacer to full rate (no pause) before running and resets both
 * MCDMA directions on exit.
 *
 * Usage:
 *   fault-inject          run the baseline (expect every channel ok)
 *   fault-inject nosync   skip the cache flush (expect every channel corrupt)
 *
 * Prerequisites match mcdma-loopback: u-dma-buf loaded with the UDMABUF_NAME
 * region, the MCDMA reachable as /dev/mcdma (pl-reg, non-root) or via /dev/mem,
 * and the pacers as /dev/rate_cfg (pl-reg). The boot-time chmod makes the
 * u-dma-buf sysfs sync controls writable, so this runs as an ordinary user.
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
#include <time.h>
#include <unistd.h>

/* ------------------------------------------------------------------ config -- */

#define NUM_CH          8               /* channels per direction (match num_ch) */
#define BUF_WORDS       512             /* 32-bit words per channel payload      */
#define BUF_BYTES       (BUF_WORDS * 4)

#define DESC_ALIGN      64              /* MCDMA SG descriptor size / alignment  */
#define DESC_AREA_BYTES 0x1000          /* room for all descriptors, 4 KiB       */

#define PAYLOAD_OFFSET  DESC_AREA_BYTES
#define REGION_BYTES    (PAYLOAD_OFFSET + NUM_CH * 2 * BUF_BYTES)

#define UDMABUF_NAME    "udmabuf0"
#define UDMABUF_DEV     "/dev/" UDMABUF_NAME
#define UDMABUF_SYS     "/sys/class/u-dma-buf/" UDMABUF_NAME

#define MCDMA_DEV       "/dev/mcdma"    /* pl-reg node, if bound (non-root)       */
#define MCDMA_MEM_BASE  0x40400000UL    /* /dev/mem fallback (block_design.tcl)   */
#define MCDMA_WIN_BYTES 0x10000UL       /* control-window size (64K)              */

#define RATE_CFG_DEV    "/dev/rate_cfg" /* pl-reg node for the axi_rate_gen cfg   */
#define RATE_MAP_SIZE   0x1000UL        /* one page covers the cfg window         */

#define POLL_TIMEOUT_US 1000000         /* completion bound; both modes finish    */
                                        /* in ~ms, so a timeout means a stray     */
                                        /* paused/throttled pacer, not a fault     */

/* ---------------------------------------------------- MCDMA register offsets -- */
/* Same map as mcdma-loopback.c; confirmed against mainline xilinx_dma.c. */

#define MM2S_CTRL       0x000
#define MM2S_SR         0x004
#define MM2S_CHEN       0x008
#define MM2S_CH_ERR     0x010
#define S2MM_CTRL       0x500
#define S2MM_SR         0x504
#define S2MM_CHEN       0x508
#define S2MM_CH_ERR     0x510

#define MM2S_CH_BASE(n) (0x040 + ((n) - 1) * 0x40)
#define S2MM_CH_BASE(n) (0x540 + ((n) - 1) * 0x40)
#define CH_CR           0x00
#define CH_SR           0x04
#define CH_CURDESC      0x08
#define CH_CURDESC_MSB  0x0C
#define CH_TAILDESC     0x10
#define CH_TAILDESC_MSB 0x14

#define CR_RS           0x00000001
#define CR_RESET        0x00000004
#define SR_HALTED       0x00000001

#define DESC_CTRL_SOF   0x80000000
#define DESC_CTRL_EOF   0x40000000
#define DESC_CTRL_LEN_MASK 0x03FFFFFF
#define DESC_STAT_CMPLT 0x80000000
#define DESC_STAT_LEN_MASK 0x03FFFFFF

struct mcdma_desc {
  uint32_t nxtdesc;
  uint32_t nxtdesc_msb;
  uint32_t buffer_addr;
  uint32_t buffer_addr_msb;
  uint32_t rsvd;
  uint32_t control;                     /* 0x14  SOF | EOF | length               */
  uint32_t status;                      /* 0x18  CMPLT | transferred length       */
  uint32_t sideband_status;
  uint32_t app[8];
};

/* ------------------------------------------------------- outcome classes -- */

/* Per-channel outcome classes (indices into class_name[]). */
enum outcome { OUT_OK = 0, OUT_CORRUPT, OUT_ERROR, OUT_INCOMPLETE };
static const char *const class_name[] = { "ok", "corrupt", "error", "incomplete" };

/* ------------------------------------------------------------- small helpers -- */

static void reg_w(volatile uint8_t *base, uint32_t off, uint32_t val)
{
  *(volatile uint32_t *)(base + off) = val;
}

static uint32_t reg_r(volatile uint8_t *base, uint32_t off)
{
  return *(volatile uint32_t *)(base + off);
}

static int64_t now_us(void)
{
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (int64_t)t.tv_sec * 1000000 + t.tv_nsec / 1000;
}

static int sysfs_read_num(const char *path, uint64_t *out)
{
  FILE *f = fopen(path, "r");
  if (!f) {
    fprintf(stderr, "open %s: %s\n", path, strerror(errno));
    return -1;
  }
  char buf[64] = {0};
  char *p = fgets(buf, sizeof(buf), f);
  fclose(f);
  if (!p)
    return -1;
  *out = strtoull(buf, NULL, 0);
  return 0;
}

/* Trigger a u-dma-buf cache sync over [offset, offset+size). `attr` is
 * "sync_for_device" (flush before DMA) or "sync_for_cpu" (invalidate after). */
static int udmabuf_sync(const char *attr, uint64_t offset, uint64_t size)
{
  char path[128];
  snprintf(path, sizeof(path), UDMABUF_SYS "/%s", attr);

  int fd = open(path, O_WRONLY);
  if (fd < 0) {
    fprintf(stderr, "open %s: %s\n", path, strerror(errno));
    return -1;
  }
  char buf[32];
  int len = snprintf(buf, sizeof(buf), "0x%08" PRIX64 "%08" PRIX64,
                     (uint64_t)(offset & 0xFFFFFFFF),
                     (uint64_t)((size & 0xFFFFFFF0ULL) | (0u << 2) | 1u));
  int rc = (write(fd, buf, len) == len) ? 0 : -1;
  if (rc)
    fprintf(stderr, "write %s: %s\n", path, strerror(errno));
  close(fd);
  return rc;
}

/* ------------------------------------------------------------- window maps -- */

/* Prefer the non-root pl-reg MCDMA node; fall back to /dev/mem. */
static volatile uint8_t *map_control_window(int *fd_out)
{
  int fd = open(MCDMA_DEV, O_RDWR);
  if (fd >= 0) {
    void *p = mmap(NULL, MCDMA_WIN_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (p != MAP_FAILED) {
      printf("MCDMA control: %s (pl-reg, no root)\n", MCDMA_DEV);
      *fd_out = fd;
      return p;
    }
    close(fd);
  }

  fd = open("/dev/mem", O_RDWR | O_SYNC);
  if (fd < 0) {
    fprintf(stderr, "open /dev/mem: %s (and %s not present)\n",
            strerror(errno), MCDMA_DEV);
    return NULL;
  }
  void *p = mmap(NULL, MCDMA_WIN_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED,
                 fd, MCDMA_MEM_BASE);
  if (p == MAP_FAILED) {
    fprintf(stderr, "mmap /dev/mem @ 0x%lx: %s\n", MCDMA_MEM_BASE, strerror(errno));
    close(fd);
    return NULL;
  }
  printf("MCDMA control: /dev/mem @ 0x%lx (root)\n", MCDMA_MEM_BASE);
  *fd_out = fd;
  return p;
}

/* Map the axi_rate_gen cfg window (pl-reg, non-root), used only to clear the
 * pacers to full rate so a prior rate-ctl run cannot stall this test. */
static volatile uint32_t *map_rate_cfg(int *fd_out)
{
  int fd = open(RATE_CFG_DEV, O_RDWR);
  if (fd < 0) {
    fprintf(stderr, "open %s: %s\n", RATE_CFG_DEV, strerror(errno));
    if (errno == ENOENT)
      fprintf(stderr, "  Is pl-reg loaded and bound? (dmesg | grep pl-reg)\n");
    return NULL;
  }
  void *p = mmap(NULL, RATE_MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (p == MAP_FAILED) {
    fprintf(stderr, "mmap %s: %s\n", RATE_CFG_DEV, strerror(errno));
    close(fd);
    return NULL;
  }
  *fd_out = fd;
  return p;
}

/* ------------------------------------------------------------- descriptors -- */

static void build_desc(struct mcdma_desc *d, uint64_t self_phys,
                       uint64_t buf_phys, uint32_t len)
{
  memset(d, 0, sizeof(*d));
  d->nxtdesc         = (uint32_t)self_phys;
  d->nxtdesc_msb     = (uint32_t)(self_phys >> 32);
  d->buffer_addr     = (uint32_t)buf_phys;
  d->buffer_addr_msb = (uint32_t)(buf_phys >> 32);
  d->control         = DESC_CTRL_SOF | DESC_CTRL_EOF | (len & DESC_CTRL_LEN_MASK);
}

static void arm_channel(volatile uint8_t *r, uint32_t ch_base, uint32_t chen,
                        int ch, uint64_t desc_phys)
{
  reg_w(r, ch_base + CH_CURDESC,     (uint32_t)desc_phys);
  reg_w(r, ch_base + CH_CURDESC_MSB, (uint32_t)(desc_phys >> 32));
  reg_w(r, chen, reg_r(r, chen) | (1u << (ch - 1)));
  reg_w(r, ch_base + CH_CR, reg_r(r, ch_base + CH_CR) | CR_RS);
}

static void trigger_channel(volatile uint8_t *r, uint32_t ch_base, uint64_t desc_phys)
{
  reg_w(r, ch_base + CH_TAILDESC,     (uint32_t)desc_phys);
  reg_w(r, ch_base + CH_TAILDESC_MSB, (uint32_t)(desc_phys >> 32));
}

static void run_direction(volatile uint8_t *r, uint32_t ctrl)
{
  reg_w(r, ctrl, reg_r(r, ctrl) | CR_RS);
  int64_t deadline = now_us() + POLL_TIMEOUT_US;
  while (reg_r(r, ctrl + 0x04) & SR_HALTED) {
    if (now_us() > deadline) {
      fprintf(stderr, "warning: MCDMA direction (ctrl 0x%x) stayed halted\n", ctrl);
      break;
    }
  }
}

static void reset_direction(volatile uint8_t *r, uint32_t ctrl)
{
  reg_w(r, ctrl, CR_RESET);
  int64_t deadline = now_us() + POLL_TIMEOUT_US;
  while (reg_r(r, ctrl) & CR_RESET) {
    if (now_us() > deadline) {
      fprintf(stderr, "warning: MCDMA reset (ctrl 0x%x) did not clear\n", ctrl);
      break;
    }
  }
}

/* --------------------------------------------------------------------- main -- */

int main(int argc, char **argv)
{
  /* 1. Parse the mode ------------------------------------------------------- */
  int nosync = 0;
  if (argc == 1) {
    nosync = 0;
  } else if (argc == 2 && strcmp(argv[1], "nosync") == 0) {
    nosync = 1;
  } else {
    fprintf(stderr,
            "Usage:\n"
            "  %s          run the baseline (expect every channel ok)\n"
            "  %s nosync   skip the cache flush (expect every channel corrupt)\n",
            argv[0], argv[0]);
    return EXIT_FAILURE;
  }

  printf("fault-inject: %d-channel MCDMA cache-coherency check\n", NUM_CH);
  printf(nosync ? "mode: nosync -- skip payload sync_for_device (expect every channel corrupt)\n\n"
                : "mode: baseline -- full sync (expect every channel ok)\n\n");

  /* 2. Map the MCDMA control window and the pacer cfg ------------------------ */
  int reg_fd = -1, cfg_fd = -1;
  volatile uint8_t *r = map_control_window(&reg_fd);
  if (!r)
    return EXIT_FAILURE;
  volatile uint32_t *cfg = map_rate_cfg(&cfg_fd);
  if (!cfg) {
    munmap((void *)r, MCDMA_WIN_BYTES);
    close(reg_fd);
    return EXIT_FAILURE;
  }

  /* Clear every pacer to full rate / not paused, so a prior rate-ctl run
   * cannot stall this coherency test. */
  for (int i = 0; i < NUM_CH; i++)
    cfg[i] = 0;

  /* 3. DMA memory ----------------------------------------------------------- */
  int buf_fd = open(UDMABUF_DEV, O_RDWR);
  if (buf_fd < 0) {
    fprintf(stderr, "open %s: %s\n", UDMABUF_DEV, strerror(errno));
    if (errno == ENOENT)
      fprintf(stderr, "  Is u-dma-buf loaded with a '%s' region? (dmesg | grep u-dma-buf)\n",
              UDMABUF_NAME);
    goto fail;
  }

  uint64_t region_phys = 0, region_size = 0;
  if (sysfs_read_num(UDMABUF_SYS "/phys_addr", &region_phys) ||
      sysfs_read_num(UDMABUF_SYS "/size", &region_size)) {
    fprintf(stderr, "could not read u-dma-buf phys_addr/size\n");
    goto fail;
  }
  if (region_size < REGION_BYTES) {
    fprintf(stderr, "%s is %" PRIu64 " bytes, need %d\n",
            UDMABUF_NAME, region_size, REGION_BYTES);
    goto fail;
  }

  uint8_t *region = mmap(NULL, REGION_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED,
                         buf_fd, 0);
  if (region == MAP_FAILED) {
    fprintf(stderr, "mmap %s: %s\n", UDMABUF_DEV, strerror(errno));
    goto fail;
  }
  printf("u-dma-buf %s: phys 0x%" PRIx64 ", %d bytes used of %" PRIu64 "\n\n",
         UDMABUF_NAME, region_phys, REGION_BYTES, region_size);

  struct mcdma_desc *mm2s_desc = (struct mcdma_desc *)(region);
  struct mcdma_desc *s2mm_desc = (struct mcdma_desc *)(region + NUM_CH * DESC_ALIGN);
  uint64_t mm2s_desc_phys = region_phys;
  uint64_t s2mm_desc_phys = region_phys + NUM_CH * DESC_ALIGN;

  uint8_t *src[NUM_CH], *dst[NUM_CH];
  uint64_t src_phys[NUM_CH], dst_phys[NUM_CH];
  for (int i = 0; i < NUM_CH; i++) {
    uint32_t off = PAYLOAD_OFFSET + i * 2 * BUF_BYTES;
    src[i]      = region + off;
    dst[i]      = region + off + BUF_BYTES;
    src_phys[i] = region_phys + off;
    dst_phys[i] = region_phys + off + BUF_BYTES;
  }

  /* 4. Build descriptors and stage a zero payload. The descriptors are flushed
   *    to DDR in BOTH modes, so the engine always runs cleanly -- the only
   *    variable is the payload sync. This flush also lays down the all-zero
   *    payload that the DMA will read as stale content in nosync. */
  for (int i = 0; i < NUM_CH; i++) {
    memset(src[i], 0, BUF_BYTES);
    memset(dst[i], 0, BUF_BYTES);
    build_desc(&mm2s_desc[i], mm2s_desc_phys + i * DESC_ALIGN,
               src_phys[i], BUF_BYTES);
    build_desc(&s2mm_desc[i], s2mm_desc_phys + i * DESC_ALIGN,
               dst_phys[i], BUF_BYTES);
  }
  if (udmabuf_sync("sync_for_device", 0, REGION_BYTES)) {
    munmap(region, REGION_BYTES);
    goto fail;
  }

  /* 5. Write the real per-channel pattern into src. The baseline flushes it so
   *    the DMA sends it; nosync deliberately skips this flush, so the DMA keeps
   *    reading the stale zeros staged above and every dst comes back all-zero. */
  for (int i = 0; i < NUM_CH; i++) {
    uint32_t *s = (uint32_t *)src[i];
    for (int w = 0; w < BUF_WORDS; w++)
      s[w] = (uint32_t)((i << 24) | (w & 0x00FFFFFF));
  }
  if (!nosync) {
    if (udmabuf_sync("sync_for_device", PAYLOAD_OFFSET, NUM_CH * 2 * BUF_BYTES)) {
      munmap(region, REGION_BYTES);
      goto fail;
    }
  } else {
    printf("(skipping the payload sync_for_device -- the DMA will read stale DDR)\n\n");
  }

  /* 6. Reset both directions, arm every channel, run, trigger --------------- */
  reset_direction(r, S2MM_CTRL);
  reset_direction(r, MM2S_CTRL);

  for (int i = 0; i < NUM_CH; i++)
    arm_channel(r, S2MM_CH_BASE(i + 1), S2MM_CHEN, i + 1, s2mm_desc_phys + i * DESC_ALIGN);
  run_direction(r, S2MM_CTRL);
  for (int i = 0; i < NUM_CH; i++)
    trigger_channel(r, S2MM_CH_BASE(i + 1), s2mm_desc_phys + i * DESC_ALIGN);

  for (int i = 0; i < NUM_CH; i++)
    arm_channel(r, MM2S_CH_BASE(i + 1), MM2S_CHEN, i + 1, mm2s_desc_phys + i * DESC_ALIGN);
  run_direction(r, MM2S_CTRL);
  for (int i = 0; i < NUM_CH; i++)
    trigger_channel(r, MM2S_CH_BASE(i + 1), mm2s_desc_phys + i * DESC_ALIGN);

  /* 7. Poll every S2MM descriptor for completion. In both modes the transfer
   *    finishes in ~ms; a timeout here means a stray throttled pacer, not a
   *    characterized fault. */
  int64_t t_start = now_us();
  int64_t deadline = t_start + POLL_TIMEOUT_US;
  int pending = 1;
  while (pending > 0 && now_us() < deadline) {
    udmabuf_sync("sync_for_cpu", NUM_CH * DESC_ALIGN, NUM_CH * DESC_ALIGN);
    pending = 0;
    for (int i = 0; i < NUM_CH; i++)
      if (!(s2mm_desc[i].status & DESC_STAT_CMPLT))
        pending++;
  }
  double elapsed_ms = (now_us() - t_start) / 1000.0;
  if (pending > 0)
    printf("note: %d channel(s) did not complete in %.1f ms "
           "-- check no pacer is left paused/throttled (rate-ctl)\n\n",
           pending, elapsed_ms);
  else
    printf("all descriptors completed in %.1f ms\n\n", elapsed_ms);

  /* 8. Read the destinations back and classify each channel. The baseline
   *    invalidates the whole payload; nosync invalidates only the destinations,
   *    leaving the cached (unflushed) src pattern intact to compare against. */
  if (!nosync) {
    udmabuf_sync("sync_for_cpu", PAYLOAD_OFFSET, NUM_CH * 2 * BUF_BYTES);
  } else {
    for (int i = 0; i < NUM_CH; i++)
      udmabuf_sync("sync_for_cpu", PAYLOAD_OFFSET + i * 2 * BUF_BYTES + BUF_BYTES,
                   BUF_BYTES);
  }

  uint32_t s2mm_ch_err = reg_r(r, S2MM_CH_ERR);
  uint32_t mm2s_ch_err = reg_r(r, MM2S_CH_ERR);

  enum outcome want = nosync ? OUT_CORRUPT : OUT_OK;

  printf("  ch  outcome     len(bytes)  desc.status  err  detail\n");
  int mismatched_expectation = 0;
  for (int i = 0; i < NUM_CH; i++) {
    uint32_t st       = s2mm_desc[i].status;
    int      cmplt    = (st & DESC_STAT_CMPLT) != 0;
    uint32_t got_len  = st & DESC_STAT_LEN_MASK;
    int      mismatch = memcmp(src[i], dst[i], BUF_BYTES) != 0;
    int      err      = ((s2mm_ch_err | mm2s_ch_err) >> i) & 1u;

    enum outcome got;
    if (err)
      got = OUT_ERROR;
    else if (!cmplt)
      got = OUT_INCOMPLETE;
    else if (mismatch || got_len != BUF_BYTES)
      got = OUT_CORRUPT;
    else
      got = OUT_OK;

    const char *flag = (got == want) ? "" : "  <-- unexpected";
    if (got != want)
      mismatched_expectation++;

    const char *detail = "";
    if (got == OUT_CORRUPT)         detail = "completed but dst != src";
    else if (got == OUT_ERROR)      detail = "CH_ERR set";
    else if (got == OUT_INCOMPLETE) detail = "descriptor never completed";

    printf("  %2d  %-10s  %9u   0x%08x   %d   %s%s\n",
           i, class_name[got], got_len, st, err, detail, flag);
  }

  printf("\n  MM2S SR=0x%08x CH_ERR=0x%08x   S2MM SR=0x%08x CH_ERR=0x%08x\n",
         reg_r(r, MM2S_SR), mm2s_ch_err, reg_r(r, S2MM_SR), s2mm_ch_err);

  /* 9. Leave the system clean: reset both directions ------------------------ */
  reset_direction(r, MM2S_CTRL);
  reset_direction(r, S2MM_CTRL);

  munmap(region, REGION_BYTES);
  munmap((void *)cfg, RATE_MAP_SIZE);
  munmap((void *)r, MCDMA_WIN_BYTES);
  close(buf_fd);
  close(cfg_fd);
  close(reg_fd);

  if (mismatched_expectation) {
    printf("\nFAIL: %d channel(s) did not match the expected outcome (%s)\n",
           mismatched_expectation, class_name[want]);
    return EXIT_FAILURE;
  }
  printf("\nPASS: every channel produced its expected outcome (%s)\n", class_name[want]);
  return EXIT_SUCCESS;

fail:
  if (cfg)
    munmap((void *)cfg, RATE_MAP_SIZE);
  if (cfg_fd >= 0)
    close(cfg_fd);
  if (buf_fd >= 0)
    close(buf_fd);
  munmap((void *)r, MCDMA_WIN_BYTES);
  close(reg_fd);
  return EXIT_FAILURE;
}
