/* halt-reset -- coordinated halt / FIFO clear / reinit / re-run of the MCDMA
 * datapath. Companion to mcdma-loopback (the happy-path round trip), rate-ctl
 * (the per-channel pacers), and fault-inject (the cache-coherency check).
 *
 * This is the DMA's off/on path. In rev_d_shim the only response to a fault or a
 * shutdown is halt/reset -- the PS never times out on a channel that is merely
 * waiting for a trigger. A FIFO-only reset (rev_d_shim's axi_sys_ctrl
 * data_buf_reset) is *not* safe to pulse while an MCDMA channel is mid-transfer:
 * the MM2S side loses byte-count sync and the S2MM side loses TLAST framing while
 * the MCDMA's own descriptor/run state is left untouched, so engine and FIFO
 * desync. The safe sequence is therefore ordered:
 *
 *   1. halt   the MCDMA (soft-reset both directions, so no master is driving the
 *             datapath),
 *   2. clear  the datapath FIFOs (write buf_reset bit i = 1, then 0), flushing
 *             any data stranded in a channel's DAC/ADC FIFO,
 *   3. reinit the descriptor rings in DDR,
 *   4. re-run and confirm every channel round-trips byte-exact.
 *
 * To have something real to clear, the tool first *strands* data: it pushes a
 * short, complete packet (STRAND_WORDS, with TLAST) into each channel's DAC FIFO
 * with that channel's pacer paused, so the packet lodges in the FIFO and never
 * reaches S2MM. Then it runs the coordinated recovery above with a fresh
 * full-length payload and a different fill pattern, and checks the round trip.
 *
 *   (no arg)  Full sequence: halt, clear the FIFOs, reinit, re-run.
 *             Expected outcome: every channel `ok` (byte-exact after the clear).
 *
 *   noclear   Same sequence but skip step 2 (do not pulse buf_reset). The
 *             stranded short packet is still sitting in each DAC FIFO, so the
 *             re-run drains that stale packet first and S2MM completes early on
 *             its TLAST -- every channel comes back short and mismatched.
 *             Expected outcome: every channel `corrupt`. This proves the FIFO
 *             clear is load-bearing.
 *
 * The tool knows what it injected, so it checks each channel's observed class
 * against the expected one and prints PASS/FAIL for the run as a whole.
 *
 * It reuses mcdma-loopback's prebuffered flow and register model (see that file
 * for the MCDMA register map and SG descriptor layout notes). It also maps the
 * axi_rate_gen cfg window to pause/unpause the pacers and the buf_reset window to
 * clear the FIFOs -- both non-root via pl-reg.
 *
 * Usage:
 *   halt-reset          halt, clear FIFOs, reinit, re-run (expect every ch ok)
 *   halt-reset noclear  skip the FIFO clear (expect every ch corrupt)
 *
 * Prerequisites match mcdma-loopback: u-dma-buf loaded with the UDMABUF_NAME
 * region, the MCDMA reachable as /dev/mcdma (pl-reg, non-root) or via /dev/mem,
 * the pacers as /dev/rate_cfg and the FIFO reset as /dev/buf_reset (both pl-reg).
 * The boot-time chmod makes the u-dma-buf sysfs sync controls writable, so this
 * runs as an ordinary user.
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
#define STRAND_WORDS    64              /* short packet stranded in the DAC FIFO */
#define STRAND_BYTES    (STRAND_WORDS * 4)

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
#define BUF_RESET_DEV   "/dev/buf_reset"/* pl-reg node for the FIFO buf_reset     */
#define REG_MAP_SIZE    0x1000UL        /* one page covers each small window      */

#define PAUSE_BIT       (1u << 16)      /* axi_rate_gen cfg PAUSE bit             */

#define POLL_TIMEOUT_US 1000000         /* completion bound for the clean re-run  */
#define STRAND_WAIT_US  50000           /* brief wait to confirm the strand stall */

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

static void sleep_us(int64_t us)
{
  struct timespec t = { .tv_sec = us / 1000000, .tv_nsec = (us % 1000000) * 1000 };
  nanosleep(&t, NULL);
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

/* Map a small pl-reg register window (rate_cfg or buf_reset), non-root. */
static volatile uint32_t *map_reg_window(const char *path, int *fd_out)
{
  int fd = open(path, O_RDWR);
  if (fd < 0) {
    fprintf(stderr, "open %s: %s\n", path, strerror(errno));
    if (errno == ENOENT)
      fprintf(stderr, "  Is pl-reg loaded and bound? (dmesg | grep pl-reg)\n");
    return NULL;
  }
  void *p = mmap(NULL, REG_MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (p == MAP_FAILED) {
    fprintf(stderr, "mmap %s: %s\n", path, strerror(errno));
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

/* --------------------------------------------------------------- patterns -- */

/* Two distinct fill patterns so a stale strand is visibly different from the
 * clean re-run. `strand` flips the middle byte, which is 0 in the clean pattern
 * (payload words are < 2^24), so the two never collide for any word index. */
static void fill_pattern(uint32_t *buf, int ch, int words, int strand)
{
  uint32_t tag = strand ? 0x00AA0000u : 0x00000000u;
  for (int w = 0; w < words; w++)
    buf[w] = ((uint32_t)ch << 24) | tag | (uint32_t)(w & 0x0000FFFF);
}

/* Reset both MCDMA directions, arm the selected channels, run and trigger. Both
 * directions are always reset first; `run_s2mm` / `run_mm2s` select which side is
 * armed (the strand phase runs the source only). */
static void start_transfer(volatile uint8_t *r,
                           uint64_t mm2s_desc_phys, uint64_t s2mm_desc_phys,
                           int run_s2mm, int run_mm2s)
{
  reset_direction(r, S2MM_CTRL);
  reset_direction(r, MM2S_CTRL);

  if (run_s2mm) {
    for (int i = 0; i < NUM_CH; i++)
      arm_channel(r, S2MM_CH_BASE(i + 1), S2MM_CHEN, i + 1, s2mm_desc_phys + i * DESC_ALIGN);
    run_direction(r, S2MM_CTRL);
    for (int i = 0; i < NUM_CH; i++)
      trigger_channel(r, S2MM_CH_BASE(i + 1), s2mm_desc_phys + i * DESC_ALIGN);
  }
  if (run_mm2s) {
    for (int i = 0; i < NUM_CH; i++)
      arm_channel(r, MM2S_CH_BASE(i + 1), MM2S_CHEN, i + 1, mm2s_desc_phys + i * DESC_ALIGN);
    run_direction(r, MM2S_CTRL);
    for (int i = 0; i < NUM_CH; i++)
      trigger_channel(r, MM2S_CH_BASE(i + 1), mm2s_desc_phys + i * DESC_ALIGN);
  }
}

/* --------------------------------------------------------------------- main -- */

int main(int argc, char **argv)
{
  /* 1. Parse the mode ------------------------------------------------------- */
  int noclear = 0;
  if (argc == 1) {
    noclear = 0;
  } else if (argc == 2 && strcmp(argv[1], "noclear") == 0) {
    noclear = 1;
  } else {
    fprintf(stderr,
            "Usage:\n"
            "  %s          halt, clear FIFOs, reinit, re-run (expect every ch ok)\n"
            "  %s noclear  skip the FIFO clear (expect every ch corrupt)\n",
            argv[0], argv[0]);
    return EXIT_FAILURE;
  }

  printf("halt-reset: %d-channel coordinated halt / FIFO clear / reinit / re-run\n",
         NUM_CH);
  printf(noclear
         ? "mode: noclear -- skip the FIFO clear (expect every channel corrupt)\n\n"
         : "mode: clear -- full sequence (expect every channel ok)\n\n");

  /* 2. Map the MCDMA control window, the pacer cfg, and the FIFO reset ------- */
  int reg_fd = -1, cfg_fd = -1, rst_fd = -1;
  volatile uint8_t *r = map_control_window(&reg_fd);
  if (!r)
    return EXIT_FAILURE;
  volatile uint32_t *cfg = map_reg_window(RATE_CFG_DEV, &cfg_fd);
  volatile uint32_t *buf_rst = map_reg_window(BUF_RESET_DEV, &rst_fd);
  if (!cfg || !buf_rst) {
    if (cfg) { munmap((void *)cfg, REG_MAP_SIZE); close(cfg_fd); }
    if (buf_rst) { munmap((void *)buf_rst, REG_MAP_SIZE); close(rst_fd); }
    munmap((void *)r, MCDMA_WIN_BYTES);
    close(reg_fd);
    return EXIT_FAILURE;
  }

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

  /* 4. Strand a short packet in each DAC FIFO. Pause every pacer so the packet
   *    lodges in the FIFO, fill src with the strand pattern, and build a short
   *    MM2S descriptor (STRAND_WORDS). Run MM2S only -- the receiver stays idle,
   *    so the packet cannot leave the FIFO. --------------------------------- */
  for (int i = 0; i < NUM_CH; i++)
    cfg[i] = PAUSE_BIT;                            /* freeze each channel's pacer */

  for (int i = 0; i < NUM_CH; i++) {
    fill_pattern((uint32_t *)src[i], i, STRAND_WORDS, 1);
    build_desc(&mm2s_desc[i], mm2s_desc_phys + i * DESC_ALIGN,
               src_phys[i], STRAND_BYTES);
  }
  if (udmabuf_sync("sync_for_device", 0, REGION_BYTES)) {
    munmap(region, REGION_BYTES);
    goto fail;
  }
  printf("stranding a %d-word packet in each DAC FIFO (pacers paused)...\n", STRAND_WORDS);
  start_transfer(r, mm2s_desc_phys, s2mm_desc_phys, 0, 1);

  /* Give MM2S time to push the short packet into the FIFOs, then confirm the
   *  data is stranded: MM2S accepted the packet but, with the pacers paused,
   *  it cannot advance to S2MM. */
  sleep_us(STRAND_WAIT_US);
  printf("  MM2S SR=0x%08x CH_ERR=0x%08x  (data now held in the DAC FIFOs)\n\n",
         reg_r(r, MM2S_SR), reg_r(r, MM2S_CH_ERR));

  /* 5. Coordinated recovery ------------------------------------------------- */

  /* 5a. HALT: soft-reset both directions so no MCDMA master drives the datapath
   *     while the FIFOs are cleared. */
  printf("halt: soft-resetting both MCDMA directions\n");
  reset_direction(r, MM2S_CTRL);
  reset_direction(r, S2MM_CTRL);

  /* 5b. CLEAR: pulse buf_reset for every channel (bit i clears channel i's DAC
   *     and ADC FIFO). Skipped in noclear mode, leaving the stranded packet in
   *     place. */
  if (!noclear) {
    uint32_t all = (NUM_CH >= 32) ? 0xFFFFFFFFu : ((1u << NUM_CH) - 1);
    printf("clear: pulsing buf_reset = 0x%02x to flush the datapath FIFOs\n", all);
    buf_rst[0] = all;
    sleep_us(1000);                               /* hold the reset well clear   */
    buf_rst[0] = 0;
    sleep_us(1000);
  } else {
    printf("clear: SKIPPED (noclear) -- the stranded packet stays in the FIFOs\n");
  }

  /* 5c. REINIT: fresh full-length payload with the clean pattern, cleared
   *     destinations, and rebuilt descriptors, flushed to DDR. The pacers stay
   *     paused here, so any data still sitting in a DAC FIFO cannot move yet. */
  printf("reinit: rebuilding the descriptor rings with a fresh payload\n");
  for (int i = 0; i < NUM_CH; i++) {
    fill_pattern((uint32_t *)src[i], i, BUF_WORDS, 0);
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

  /* 5d. RE-RUN: arm and start both directions while the pacers are still paused,
   *     so the receiver is capturing before any data is released. Releasing the
   *     pacers only after S2MM is armed is what makes the clear observable: a soft
   *     reset drains data already at the MCDMA S2MM input, so if the stranded
   *     packet were released before this point it would be flushed either way. */
  printf("re-run: transferring the fresh payload\n\n");
  start_transfer(r, mm2s_desc_phys, s2mm_desc_phys, 1, 1);

  /* 5e. RELEASE: unpause the pacers so data flows into the armed receiver. In
   *     clear mode the FIFOs are empty, so only the fresh payload is captured and
   *     every channel is byte-exact. In noclear the stranded packet is still at
   *     the head of each DAC FIFO, so it is captured first and S2MM completes
   *     early on its TLAST -- short and mismatched. That difference is what proves
   *     the FIFO clear is load-bearing. */
  for (int i = 0; i < NUM_CH; i++)
    cfg[i] = 0;

  /* 6. Poll every S2MM descriptor for completion ---------------------------- */
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
    printf("note: %d channel(s) did not complete in %.1f ms\n\n", pending, elapsed_ms);
  else
    printf("all descriptors completed in %.1f ms\n\n", elapsed_ms);

  /* 7. Invalidate the payloads and classify each channel against the clean
   *    pattern. In clear mode every channel should be byte-exact; in noclear the
   *    stranded strand-pattern packet drains first, so each channel is short and
   *    mismatched (corrupt). --------------------------------------------------*/
  udmabuf_sync("sync_for_cpu", PAYLOAD_OFFSET, NUM_CH * 2 * BUF_BYTES);

  uint32_t s2mm_ch_err = reg_r(r, S2MM_CH_ERR);
  uint32_t mm2s_ch_err = reg_r(r, MM2S_CH_ERR);

  enum outcome want = noclear ? OUT_CORRUPT : OUT_OK;

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

  /* 8. Leave the system clean: unpause pacers, clear the FIFOs, reset MCDMA. -- */
  for (int i = 0; i < NUM_CH; i++)
    cfg[i] = 0;
  buf_rst[0] = (NUM_CH >= 32) ? 0xFFFFFFFFu : ((1u << NUM_CH) - 1);
  sleep_us(1000);
  buf_rst[0] = 0;
  reset_direction(r, MM2S_CTRL);
  reset_direction(r, S2MM_CTRL);

  munmap(region, REGION_BYTES);
  munmap((void *)buf_rst, REG_MAP_SIZE);
  munmap((void *)cfg, REG_MAP_SIZE);
  munmap((void *)r, MCDMA_WIN_BYTES);
  close(buf_fd);
  close(rst_fd);
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
  munmap((void *)buf_rst, REG_MAP_SIZE);
  munmap((void *)cfg, REG_MAP_SIZE);
  if (buf_fd >= 0)
    close(buf_fd);
  close(rst_fd);
  close(cfg_fd);
  munmap((void *)r, MCDMA_WIN_BYTES);
  close(reg_fd);
  return EXIT_FAILURE;
}
