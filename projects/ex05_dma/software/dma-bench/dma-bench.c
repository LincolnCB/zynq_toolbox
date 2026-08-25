/* dma-bench -- MCDMA throughput and latency benchmark over a multi-descriptor ring.
 *
 * This is the ex05 measurement tool for the parent project's DMA sizing questions
 * (PROJECT_BRIEF section 6): what does the engine actually deliver, and how does
 * that trade off against chunk size? mcdma-loopback stays the clean integrity
 * checker; dma-bench reuses its register model, descriptor layout, and u-dma-buf
 * mapping but adds the one capability the loopback never needed: a real
 * multi-descriptor scatter-gather ring -- K descriptors per channel, each a
 * <=1024-beat packet.
 *
 * That ring shape is the correct one for the packet-atomic s2mm_mux (many small
 * packets, not one huge packet -- a single packet larger than the switch's
 * ARB_ON_MAX_XFERS backstop re-arbitrates mid-packet and corrupts framing), and it
 * de-risks the SG ring the parent project needs for continuous streaming.
 *
 * It reports four metrics:
 *
 *   1. Per-transfer latency -- start to completion for one small single-descriptor
 *      packet on one channel, min/mean/max over many runs. This is the
 *      descriptor-fetch + engine + writeback floor (software-polled, so it also
 *      includes the poll syscall floor; the true interrupt-notification latency is
 *      what dma-irq reports).
 *   2. Sustained aggregate throughput -- total payload bytes / engine-busy time
 *      with all NUM_CH channels running full rate, swept over chunk size.
 *   3. Overhead vs. chunk size -- the sweep itself: total bytes per channel held
 *      fixed so the points are comparable. Small chunks add per-packet overhead;
 *      large chunks amortize it.
 *   4. Worst-case per-channel service gap -- derived from the round-robin model:
 *      the s2mm_mux is packet-atomic round-robin, so between two service windows a
 *      channel waits while the other (NUM_CH - 1) channels are each serviced one
 *      packet. gap = (NUM_CH - 1) * (engine-busy / total-packets). This sets the
 *      minimum ADC/DAC FIFO depth in the parent.
 *
 * Methodology: the first (cold) iteration of every measurement is discarded and
 * steady state reported; engine-busy time (trigger to all-complete) is timed
 * separately from the one-time sync_for_* CPU cost; the throughput/gap runs are at
 * full rate (the pacer transparent) so data is always available -- the true worst
 * case for arbitration.
 *
 * The MCDMA register map, SG descriptor layout (control at 0x14, SOF/EOF at
 * 31/30), and start sequence all match mcdma-loopback.c and mainline
 * drivers/dma/xilinx/xilinx_dma.c. No arguments: dma-bench runs the full suite.
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

#define NUM_CH             8            /* channels per direction (match num_ch)  */

/* Fixed payload per channel per direction, held constant across the chunk sweep
 * so throughput points are comparable. A power of two divisible by every chunk
 * size below. */
#define TOTAL_WORDS_PER_CH 16384        /* 64 KiB/channel/direction               */
#define TOTAL_BYTES_PER_CH (TOTAL_WORDS_PER_CH * 4)

#define DESC_ALIGN         64           /* MCDMA SG descriptor size / alignment   */

/* Smallest chunk in the sweep sets the largest ring; the descriptor area is sized
 * for that worst case so rings never overlap as K changes. */
#define MIN_CHUNK_WORDS    32
#define MAX_DESC_PER_CH    (TOTAL_WORDS_PER_CH / MIN_CHUNK_WORDS)   /* 512         */

/* Descriptor area holds MM2S then S2MM rings, each NUM_CH * MAX_DESC_PER_CH
 * descriptors, then the per-channel src/dst payload pair follows. */
#define RING_STRIDE        (MAX_DESC_PER_CH * DESC_ALIGN)           /* per channel */
#define MM2S_RING_OFFSET   0
#define S2MM_RING_OFFSET   (NUM_CH * RING_STRIDE)
#define DESC_AREA_BYTES    (2 * NUM_CH * RING_STRIDE)
#define PAYLOAD_OFFSET     DESC_AREA_BYTES
#define REGION_BYTES       (PAYLOAD_OFFSET + NUM_CH * 2 * TOTAL_BYTES_PER_CH)

#define UDMABUF_NAME       "udmabuf0"
#define UDMABUF_DEV        "/dev/" UDMABUF_NAME
#define UDMABUF_SYS        "/sys/class/u-dma-buf/" UDMABUF_NAME

#define MCDMA_DEV          "/dev/mcdma"   /* pl-reg node, if bound (non-root)      */
#define MCDMA_MEM_BASE     0x40400000UL   /* /dev/mem fallback (block_design.tcl)  */
#define MCDMA_WIN_BYTES    0x10000UL      /* control-window size (64K)             */

#define POLL_TIMEOUT_US    2000000        /* 2 s of polling before giving up       */

#define FCLK_HZ            100000000.0    /* datapath clock (block_design.tcl)     */
#define HP_BUS_BYTES       8              /* HP0 is 64-bit                          */

/* Measurement iteration counts (one extra cold run is always discarded). */
#define LAT_CHUNK_WORDS    64            /* single-packet latency probe size       */
#define LAT_ITERS          64
#define SWEEP_ITERS        6
#define SWEEP_LAT_ITERS    4

/* Chunk sizes to sweep, in 32-bit beats. All divide TOTAL_WORDS_PER_CH and stay
 * at or below the s2mm_mux ARB_ON_MAX_XFERS 1024-beat backstop. */
static const uint32_t chunk_set[] = { 32, 64, 128, 256, 512, 1024 };
#define NUM_CHUNKS (int)(sizeof(chunk_set) / sizeof(chunk_set[0]))

/* ---------------------------------------------------- MCDMA register offsets -- */

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

/* MCDMA hardware descriptor: control at 0x14, status at 0x18. 64 bytes. */
struct mcdma_desc {
  uint32_t nxtdesc;
  uint32_t nxtdesc_msb;
  uint32_t buffer_addr;
  uint32_t buffer_addr_msb;
  uint32_t rsvd;
  uint32_t control;
  uint32_t status;
  uint32_t sideband_status;
  uint32_t app[8];
};

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

/* ------------------------------------------------------- control-window map -- */

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

/* -------------------------------------------------------- benchmark context -- */

struct ctx {
  volatile uint8_t *r;         /* MCDMA control window                            */
  uint8_t          *region;    /* u-dma-buf mapping                               */
  uint64_t          region_phys;
};

/* Offsets within the single u-dma-buf region. */
static uint64_t mm2s_ring_off(int ch) { return MM2S_RING_OFFSET + (uint64_t)ch * RING_STRIDE; }
static uint64_t s2mm_ring_off(int ch) { return S2MM_RING_OFFSET + (uint64_t)ch * RING_STRIDE; }
static uint64_t src_off(int ch)       { return PAYLOAD_OFFSET + (uint64_t)ch * 2 * TOTAL_BYTES_PER_CH; }
static uint64_t dst_off(int ch)       { return src_off(ch) + TOTAL_BYTES_PER_CH; }

/* Build one channel's ring: k descriptors, each covering chunk_bytes of the
 * payload buffer, each its own SOF|EOF packet, chained cyclically. The engine
 * processes curdesc..taildesc and stops, so the cyclic link is harmless. */
static void build_ring(struct ctx *c, uint64_t ring_off, uint64_t buf_phys,
                       int k, uint32_t chunk_bytes)
{
  for (int j = 0; j < k; j++) {
    uint64_t next = c->region_phys + ring_off + (uint64_t)((j + 1) % k) * DESC_ALIGN;
    uint64_t buf  = buf_phys + (uint64_t)j * chunk_bytes;
    struct mcdma_desc *d = (struct mcdma_desc *)(c->region + ring_off + (uint64_t)j * DESC_ALIGN);
    memset(d, 0, sizeof(*d));
    d->nxtdesc         = (uint32_t)next;
    d->nxtdesc_msb     = (uint32_t)(next >> 32);
    d->buffer_addr     = (uint32_t)buf;
    d->buffer_addr_msb = (uint32_t)(buf >> 32);
    d->control         = DESC_CTRL_SOF | DESC_CTRL_EOF | (chunk_bytes & DESC_CTRL_LEN_MASK);
  }
}

static void arm_channel(volatile uint8_t *r, uint32_t ch_base, uint32_t chen,
                        int ch, uint64_t first_desc_phys)
{
  reg_w(r, ch_base + CH_CURDESC,     (uint32_t)first_desc_phys);
  reg_w(r, ch_base + CH_CURDESC_MSB, (uint32_t)(first_desc_phys >> 32));
  reg_w(r, chen, reg_r(r, chen) | (1u << (ch - 1)));
  reg_w(r, ch_base + CH_CR, reg_r(r, ch_base + CH_CR) | CR_RS);
}

static void trigger_channel(volatile uint8_t *r, uint32_t ch_base, uint64_t tail_desc_phys)
{
  reg_w(r, ch_base + CH_TAILDESC,     (uint32_t)tail_desc_phys);
  reg_w(r, ch_base + CH_TAILDESC_MSB, (uint32_t)(tail_desc_phys >> 32));
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

/* Poll each active channel's last S2MM descriptor for completion. Descriptors
 * live in DDR, so invalidate each channel's last descriptor (64 bytes) before
 * reading it. Descriptors complete in order, so the last one completing means the
 * whole channel finished. */
static int all_complete(struct ctx *c, uint32_t run_mask, int k)
{
  for (int i = 0; i < NUM_CH; i++) {
    if (!(run_mask & (1u << i)))
      continue;
    uint64_t off = s2mm_ring_off(i) + (uint64_t)(k - 1) * DESC_ALIGN;
    udmabuf_sync("sync_for_cpu", off, DESC_ALIGN);
    struct mcdma_desc *d = (struct mcdma_desc *)(c->region + off);
    if (!(d->status & DESC_STAT_CMPLT))
      return 0;
  }
  return 1;
}

/* Run one transfer: k descriptors of chunk_words each on every channel in
 * run_mask. Returns engine-busy microseconds (MM2S trigger to all-complete), or
 * -1 on timeout. If verify != 0, checks dst == src byte-for-byte and sets *ok.
 *
 * The ring build and the descriptor flush happen before the timer starts; only
 * the engine work (trigger -> completion) is timed, so the one-time sync_for_*
 * CPU cost is excluded from throughput. */
static int64_t run_transfer(struct ctx *c, uint32_t chunk_words, int k,
                            uint32_t run_mask, int verify, int *ok)
{
  uint32_t chunk_bytes = chunk_words * 4;

  /* Build the rings for every active channel. */
  for (int i = 0; i < NUM_CH; i++) {
    if (!(run_mask & (1u << i)))
      continue;
    build_ring(c, mm2s_ring_off(i), c->region_phys + src_off(i), k, chunk_bytes);
    build_ring(c, s2mm_ring_off(i), c->region_phys + dst_off(i), k, chunk_bytes);
    if (verify)
      memset(c->region + dst_off(i), 0, (size_t)k * chunk_bytes);
  }

  /* Flush descriptors (and, on a verify run, the cleared destinations) to DDR. */
  udmabuf_sync("sync_for_device", 0, DESC_AREA_BYTES);
  if (verify)
    for (int i = 0; i < NUM_CH; i++)
      if (run_mask & (1u << i))
        udmabuf_sync("sync_for_device", dst_off(i), (uint64_t)k * chunk_bytes);

  volatile uint8_t *r = c->r;
  reset_direction(r, S2MM_CTRL);
  reset_direction(r, MM2S_CTRL);

  for (int i = 0; i < NUM_CH; i++)
    if (run_mask & (1u << i))
      arm_channel(r, S2MM_CH_BASE(i + 1), S2MM_CHEN, i + 1,
                  c->region_phys + s2mm_ring_off(i));
  run_direction(r, S2MM_CTRL);
  for (int i = 0; i < NUM_CH; i++)
    if (run_mask & (1u << i))
      trigger_channel(r, S2MM_CH_BASE(i + 1),
                      c->region_phys + s2mm_ring_off(i) + (uint64_t)(k - 1) * DESC_ALIGN);

  for (int i = 0; i < NUM_CH; i++)
    if (run_mask & (1u << i))
      arm_channel(r, MM2S_CH_BASE(i + 1), MM2S_CHEN, i + 1,
                  c->region_phys + mm2s_ring_off(i));
  run_direction(r, MM2S_CTRL);

  /* Time only the engine: trigger the source, then poll to completion. */
  int64_t t0 = now_us();
  for (int i = 0; i < NUM_CH; i++)
    if (run_mask & (1u << i))
      trigger_channel(r, MM2S_CH_BASE(i + 1),
                      c->region_phys + mm2s_ring_off(i) + (uint64_t)(k - 1) * DESC_ALIGN);

  int64_t deadline = t0 + POLL_TIMEOUT_US;
  int done = 0;
  while (now_us() < deadline) {
    if (all_complete(c, run_mask, k)) {
      done = 1;
      break;
    }
  }
  int64_t busy = now_us() - t0;

  if (!done) {
    fprintf(stderr, "timeout: chunk=%u k=%d did not complete\n", chunk_words, k);
    fprintf(stderr, "  MM2S SR=0x%08x CH_ERR=0x%08x   S2MM SR=0x%08x CH_ERR=0x%08x\n",
            reg_r(r, MM2S_SR), reg_r(r, MM2S_CH_ERR),
            reg_r(r, S2MM_SR), reg_r(r, S2MM_CH_ERR));
    reset_direction(r, S2MM_CTRL);
    reset_direction(r, MM2S_CTRL);
    return -1;
  }

  if (verify) {
    *ok = 1;
    for (int i = 0; i < NUM_CH; i++) {
      if (!(run_mask & (1u << i)))
        continue;
      size_t bytes = (size_t)k * chunk_bytes;
      udmabuf_sync("sync_for_cpu", dst_off(i), bytes);
      if (memcmp(c->region + src_off(i), c->region + dst_off(i), bytes) != 0) {
        *ok = 0;
        fprintf(stderr, "  ch%d data mismatch (chunk=%u k=%d)\n", i, chunk_words, k);
      }
    }
  }

  reset_direction(r, S2MM_CTRL);
  reset_direction(r, MM2S_CTRL);
  return busy;
}

/* --------------------------------------------------------------- fill source -- */

/* One-time fill of every channel's full source buffer with a per-channel pattern,
 * flushed to DDR. The rings only ever point into the front of these buffers, so
 * the source never needs re-filling between runs. */
static int fill_sources(struct ctx *c)
{
  for (int i = 0; i < NUM_CH; i++) {
    uint32_t *s = (uint32_t *)(c->region + src_off(i));
    for (int w = 0; w < TOTAL_WORDS_PER_CH; w++)
      s[w] = (uint32_t)((i << 24) | (w & 0x00FFFFFF));
  }
  for (int i = 0; i < NUM_CH; i++)
    if (udmabuf_sync("sync_for_device", src_off(i), TOTAL_BYTES_PER_CH))
      return -1;
  return 0;
}

/* --------------------------------------------------------------------- main -- */

int main(void)
{
  printf("dma-bench: %d-channel MCDMA throughput / latency benchmark\n\n", NUM_CH);

  struct ctx c = {0};
  int reg_fd = -1;
  c.r = map_control_window(&reg_fd);
  if (!c.r)
    return EXIT_FAILURE;

  int buf_fd = open(UDMABUF_DEV, O_RDWR);   /* cached mapping (no O_SYNC)          */
  if (buf_fd < 0) {
    fprintf(stderr, "open %s: %s\n", UDMABUF_DEV, strerror(errno));
    if (errno == ENOENT)
      fprintf(stderr, "  Is u-dma-buf loaded with a '%s' region?\n", UDMABUF_NAME);
    return EXIT_FAILURE;
  }

  uint64_t region_size = 0;
  if (sysfs_read_num(UDMABUF_SYS "/phys_addr", &c.region_phys) ||
      sysfs_read_num(UDMABUF_SYS "/size", &region_size)) {
    fprintf(stderr, "could not read u-dma-buf phys_addr/size\n");
    return EXIT_FAILURE;
  }
  if (region_size < REGION_BYTES) {
    fprintf(stderr, "%s is %" PRIu64 " bytes, need %d\n",
            UDMABUF_NAME, region_size, REGION_BYTES);
    return EXIT_FAILURE;
  }

  c.region = mmap(NULL, REGION_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED, buf_fd, 0);
  if (c.region == MAP_FAILED) {
    fprintf(stderr, "mmap %s: %s\n", UDMABUF_DEV, strerror(errno));
    return EXIT_FAILURE;
  }
  printf("u-dma-buf %s: phys 0x%" PRIx64 ", %d bytes used of %" PRIu64 "\n\n",
         UDMABUF_NAME, c.region_phys, REGION_BYTES, region_size);

  if (fill_sources(&c))
    return EXIT_FAILURE;

  uint32_t all_mask = (NUM_CH >= 32) ? 0xFFFFFFFFu : ((1u << NUM_CH) - 1);

  /* Correctness gate: one verified all-channel run before trusting any timing. */
  {
    int ok = 0;
    int k = TOTAL_WORDS_PER_CH / 256;
    int64_t busy = run_transfer(&c, 256, k, all_mask, 1, &ok);
    if (busy < 0 || !ok) {
      fprintf(stderr, "correctness check FAILED -- aborting benchmark\n");
      return EXIT_FAILURE;
    }
    printf("correctness: all %d channels round-tripped (256-beat chunks, k=%d)\n\n",
           NUM_CH, k);
  }

  /* 1. Per-transfer latency: one small single-descriptor packet on one channel. */
  {
    int64_t lat_min = -1, lat_max = 0;
    double  lat_sum = 0;
    int     samples = 0;
    for (int it = 0; it < LAT_ITERS + 1; it++) {
      int64_t busy = run_transfer(&c, LAT_CHUNK_WORDS, 1, 1u << 0, 0, NULL);
      if (busy < 0)
        return EXIT_FAILURE;
      if (it == 0)                       /* discard the cold iteration            */
        continue;
      if (lat_min < 0 || busy < lat_min) lat_min = busy;
      if (busy > lat_max)                lat_max = busy;
      lat_sum += busy;
      samples++;
    }
    printf("per-transfer latency (single %d-beat packet, 1 channel, %d runs):\n",
           LAT_CHUNK_WORDS, samples);
    printf("  min %.1f us   mean %.1f us   max %.1f us\n\n",
           lat_min / 1.0, lat_sum / samples, lat_max / 1.0);
  }

  /* 2/3/4. Chunk-size sweep: throughput, derived worst-case gap, isolated
   * single-packet latency, at fixed bytes/channel over every chunk size. */
  double total_bytes = (double)NUM_CH * TOTAL_BYTES_PER_CH;
  double best_mbps = 0.0;

  printf("chunk sweep (%d words/channel fixed, all channels full rate):\n",
         TOTAL_WORDS_PER_CH);
  printf("  chunk(beats)  desc/ch  throughput(MB/s)  gap(us)  latency(us)\n");

  for (int ci = 0; ci < NUM_CHUNKS; ci++) {
    uint32_t chunk = chunk_set[ci];
    int k = TOTAL_WORDS_PER_CH / chunk;

    /* Throughput: all channels, mean engine-busy over the warm iterations. */
    double busy_sum = 0.0;
    int    got = 0;
    for (int it = 0; it < SWEEP_ITERS + 1; it++) {
      int64_t busy = run_transfer(&c, chunk, k, all_mask, 0, NULL);
      if (busy < 0)
        return EXIT_FAILURE;
      if (it == 0)
        continue;
      busy_sum += busy;
      got++;
    }
    double busy_mean_us = busy_sum / got;
    double mbps = total_bytes / busy_mean_us;         /* bytes/us == MB/s          */
    if (mbps > best_mbps)
      best_mbps = mbps;

    /* Worst-case per-channel service gap from the round-robin model. */
    double per_packet_us = busy_mean_us / ((double)NUM_CH * k);
    double gap_us = (NUM_CH - 1) * per_packet_us;

    /* Isolated single-packet latency at this chunk size (one channel, k=1). */
    int64_t lat_min = -1;
    for (int it = 0; it < SWEEP_LAT_ITERS + 1; it++) {
      int64_t busy = run_transfer(&c, chunk, 1, 1u << 0, 0, NULL);
      if (busy < 0)
        return EXIT_FAILURE;
      if (it == 0)
        continue;
      if (lat_min < 0 || busy < lat_min)
        lat_min = busy;
    }

    printf("  %10u  %7d  %16.1f  %7.2f  %11.1f\n",
           chunk, k, mbps, gap_us, lat_min / 1.0);
  }

  double ceiling_mbps = FCLK_HZ * HP_BUS_BYTES / 2.0 / 1e6;   /* read+write halves */
  printf("\nHP0 payload ceiling ~= %.0f MB/s (64-bit @ %.0f MHz, /2 for MM2S+S2MM)\n",
         ceiling_mbps, FCLK_HZ / 1e6);
  printf("best measured %.1f MB/s (%.0f%% of ceiling)\n",
         best_mbps, 100.0 * best_mbps / ceiling_mbps);

  munmap(c.region, REGION_BYTES);
  close(buf_fd);
  munmap((void *)c.r, MCDMA_WIN_BYTES);
  close(reg_fd);
  return EXIT_SUCCESS;
}
