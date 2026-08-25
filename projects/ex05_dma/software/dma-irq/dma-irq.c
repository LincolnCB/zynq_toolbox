/* dma-irq -- MCDMA completion/error interrupt via pl-irq, on the prebuffered flow.
 *
 * This is the interrupt-driven companion to mcdma-loopback. Both run the exact
 * same prebuffered transfer (u-dma-buf memory, an SG descriptor ring, one flush
 * before the run), but where mcdma-loopback *polls* each S2MM descriptor for
 * completion, this program instead blocks on the MCDMA's completion/error
 * interrupt delivered through the pl-irq misc device, and reports how long the
 * notification took to reach userspace.
 *
 * The block design OR-reduces all 2*num_ch MCDMA channel interrupts (MM2S and
 * S2MM completion/error) onto a single IRQ_F2P line, and the device tree binds
 * that line to the out-of-tree pl-irq module, which publishes it non-root as one
 * misc device (/dev/mcdma_irq, level-high). Unlike the in-tree generic-uio path
 * (ex04) this needs no kernel command line change and no chmod. The interrupt is
 * a doorbell only: on wakeup the program reads each channel's MCDMA status
 * register to see which channel(s) completed or errored, then clears those status
 * bits so the level-triggered line deasserts before the IRQ is re-armed. This is
 * the pattern rev_d_shim uses -- a single aggregated error-alert IRQ plus a poll
 * of the authoritative status word -- rather than one GIC line per channel.
 *
 * Flow:
 *   1. open the pl-irq node, the MCDMA control window, and the u-dma-buf region,
 *   2. build the same per-channel descriptors/patterns as mcdma-loopback and
 *      flush once,
 *   3. reset both directions; arm every channel with its completion and error
 *      interrupts enabled; start S2MM (the receiver) first,
 *   4. arm the pl-irq interrupt, take t_start, and start MM2S (the source),
 *   5. poll() the pl-irq node; on each wakeup record the first-notification
 *      latency, read the authoritative per-channel status, clear the interrupt
 *      status bits, and re-arm the IRQ, until every S2MM channel has completed
 *      (or a timeout),
 *   6. invalidate and verify the byte-for-byte round trip.
 *
 * The register map, descriptor layout, and start sequence all match
 * drivers/dma/xilinx/xilinx_dma.c (the MCDMA path) and mcdma-loopback.c; the only
 * additions here are the channel interrupt-enable bits and the pl-irq handshake
 * (write 1 to arm, read/poll to wait, matching UIO semantics).
 *
 * Prerequisites (see the project README and device tree):
 *   - the pl-irq module loaded (autoloaded from kernel_modules/), so the
 *     mcdma_irq node binds as /dev/mcdma_irq -- no bootargs needed,
 *   - u-dma-buf loaded with a UDMABUF_NAME region and the MCDMA reachable via the
 *     pl-reg node /dev/mcdma (non-root) or /dev/mem.
 *
 * Run with:  dma-irq
 */

#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

/* ------------------------------------------------------------------ config -- */

#define NUM_CH          8               /* channels per direction (match num_ch) */
#define BUF_WORDS       512             /* 32-bit words per channel payload      */
#define BUF_BYTES       (BUF_WORDS * 4)

#define DESC_BYTES      64              /* MCDMA SG descriptor size               */
#define DESC_ALIGN      64
#define DESC_AREA_BYTES 0x1000          /* room for all descriptors, 4 KiB       */

#define PAYLOAD_OFFSET  DESC_AREA_BYTES
#define REGION_BYTES    (PAYLOAD_OFFSET + NUM_CH * 2 * BUF_BYTES)

#define UDMABUF_NAME    "udmabuf0"
#define UDMABUF_DEV     "/dev/" UDMABUF_NAME
#define UDMABUF_SYS     "/sys/class/u-dma-buf/" UDMABUF_NAME

#define MCDMA_DEV       "/dev/mcdma"    /* pl-reg node, if bound (non-root)       */
#define MCDMA_MEM_BASE  0x40400000UL    /* /dev/mem fallback (block_design.tcl)   */
#define MCDMA_WIN_BYTES 0x10000UL       /* control-window size (64K)              */

#define PL_IRQ_DEV      "/dev/mcdma_irq" /* pl-irq misc device (DT node label)    */

#define IRQ_TIMEOUT_MS  1000            /* poll() wait before giving up            */

/* ---------------------------------------------------- MCDMA register offsets -- */
/* Confirmed against mainline drivers/dma/xilinx/xilinx_dma.c (the MCDMA path). */

#define MM2S_CTRL       0x000           /* common control (bit0 RS, bit2 reset)   */
#define MM2S_SR         0x004           /* common status (bit0 HALTED)            */
#define MM2S_CHEN       0x008           /* channel enable bitmask (bit n-1 = ch n)*/
#define MM2S_CH_ERR     0x010
#define S2MM_CTRL       0x500
#define S2MM_SR         0x504
#define S2MM_CHEN       0x508
#define S2MM_CH_ERR     0x510

#define MM2S_CH_BASE(n) (0x040 + ((n) - 1) * 0x40)
#define S2MM_CH_BASE(n) (0x540 + ((n) - 1) * 0x40)
#define CH_CR           0x00            /* channel control                        */
#define CH_SR           0x04            /* channel status                         */
#define CH_CURDESC      0x08
#define CH_CURDESC_MSB  0x0C
#define CH_TAILDESC     0x10
#define CH_TAILDESC_MSB 0x14

#define CR_RS           0x00000001      /* Run/Stop (bit 0)                        */
#define CR_RESET        0x00000004      /* soft reset (bit 2)                      */
#define SR_HALTED       0x00000001

/* Per-channel interrupt controls. MCDMA does NOT share the AXI-DMA interrupt bit
 * layout: its per-channel enables and status live at bits 5/6/7 (see
 * XILINX_MCDMA_IRQ_IOC/DELAY/ERR_MASK in drivers/dma/xilinx/xilinx_dma.c), not the
 * AXI-DMA 12/13/14. The channel CR enables interrupts and sets the completion
 * threshold; the channel SR reports which fired and is write-1-to-clear. The
 * threshold (bits [23:16], the one field MCDMA and AXI-DMA share) is the number of
 * completed packets before an I/O-completion interrupt asserts, so it must be at
 * least 1. Using the AXI-DMA positions leaves the real enables clear, so the MCDMA
 * introut line never asserts and the aggregate IRQ is never delivered. */
#define CH_CR_IOC_IRQ_EN  0x00000020    /* BIT(5) completion irq enable           */
#define CH_CR_DLY_IRQ_EN  0x00000040    /* BIT(6) delay irq enable                */
#define CH_CR_ERR_IRQ_EN  0x00000080    /* BIT(7) error irq enable                */
#define CH_CR_IRQ_EN_ALL  (CH_CR_IOC_IRQ_EN | CH_CR_ERR_IRQ_EN)
#define CH_CR_IRQ_THRESH1 0x00010000    /* threshold = 1 in bits [23:16]          */

#define CH_SR_IOC_IRQ     0x00000020    /* BIT(5)                                  */
#define CH_SR_DLY_IRQ     0x00000040    /* BIT(6)                                  */
#define CH_SR_ERR_IRQ     0x00000080    /* BIT(7)                                  */
#define CH_SR_IRQ_ALL     (CH_SR_IOC_IRQ | CH_SR_DLY_IRQ | CH_SR_ERR_IRQ)

#define DESC_CTRL_SOF   0x80000000      /* start-of-packet (BIT 31)               */
#define DESC_CTRL_EOF   0x40000000      /* end-of-packet   (BIT 30)               */
#define DESC_CTRL_LEN_MASK 0x03FFFFFF
#define DESC_STAT_CMPLT 0x80000000      /* descriptor completed (BIT 31)          */
#define DESC_STAT_LEN_MASK 0x03FFFFFF

/* MCDMA hardware descriptor: `control` is at 0x14 and `status` at 0x18 (unlike
 * the AXI-DMA BD which uses 0x18/0x1C). 64 bytes, 64-byte aligned. */
struct mcdma_desc {
  uint32_t nxtdesc;                     /* 0x00                                   */
  uint32_t nxtdesc_msb;                 /* 0x04                                   */
  uint32_t buffer_addr;                 /* 0x08                                   */
  uint32_t buffer_addr_msb;             /* 0x0C                                   */
  uint32_t rsvd;                        /* 0x10                                   */
  uint32_t control;                     /* 0x14  SOF | EOF | length               */
  uint32_t status;                      /* 0x18  CMPLT | transferred length       */
  uint32_t sideband_status;             /* 0x1C                                   */
  uint32_t app[8];                      /* 0x20-0x3F  pad to 64 bytes             */
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

/* -------------------------------------------------------- pl-irq interrupt -- */

/* Open the pl-irq misc device. It is created world-accessible (0666) and named
 * from the DT node label, so this is just a plain open of a fixed path -- no
 * /sys scan, no root, no bootargs. */
static int open_irq_dev(void)
{
  int fd = open(PL_IRQ_DEV, O_RDWR);
  if (fd < 0) {
    fprintf(stderr, "open %s: %s\n", PL_IRQ_DEV, strerror(errno));
    fprintf(stderr, "  Is the pl-irq module loaded? (dmesg | grep pl-irq)\n");
    return -1;
  }
  printf("PL interrupt: %s (pl-irq, no root)\n", PL_IRQ_DEV);
  return fd;
}

/* Arm (val=1) or mask (val=0) the interrupt. pl-irq masks the line in its handler
 * on each fire; writing 1 re-arms it (matching UIO semantics). */
static int irq_arm(int fd, uint32_t val)
{
  if (write(fd, &val, sizeof(val)) != (ssize_t)sizeof(val)) {
    fprintf(stderr, "pl-irq %s: %s\n", val ? "arm" : "mask", strerror(errno));
    return -1;
  }
  return 0;
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

/* Arm one channel with its completion and error interrupts enabled: program the
 * current descriptor, enable the channel, then set Run/Stop plus the interrupt
 * enables and a completion threshold of 1. The common Run/Stop and the tail
 * write happen after all channels are armed. */
static void arm_channel_irq(volatile uint8_t *r, uint32_t ch_base, uint32_t chen,
                            int ch, uint64_t desc_phys)
{
  reg_w(r, ch_base + CH_CURDESC,     (uint32_t)desc_phys);
  reg_w(r, ch_base + CH_CURDESC_MSB, (uint32_t)(desc_phys >> 32));
  reg_w(r, chen, reg_r(r, chen) | (1u << (ch - 1)));
  reg_w(r, ch_base + CH_CR,
        reg_r(r, ch_base + CH_CR) | CR_RS | CH_CR_IRQ_EN_ALL | CH_CR_IRQ_THRESH1);
}

static void trigger_channel(volatile uint8_t *r, uint32_t ch_base, uint64_t desc_phys)
{
  reg_w(r, ch_base + CH_TAILDESC,     (uint32_t)desc_phys);
  reg_w(r, ch_base + CH_TAILDESC_MSB, (uint32_t)(desc_phys >> 32));
}

static void run_direction(volatile uint8_t *r, uint32_t ctrl)
{
  reg_w(r, ctrl, reg_r(r, ctrl) | CR_RS);
  int64_t deadline = now_us() + 1000000;
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
  int64_t deadline = now_us() + 1000000;
  while (reg_r(r, ctrl) & CR_RESET) {
    if (now_us() > deadline) {
      fprintf(stderr, "warning: MCDMA reset (ctrl 0x%x) did not clear\n", ctrl);
      break;
    }
  }
}

/* Scan every channel's interrupt status: record which S2MM channels completed and
 * any errors, then clear the write-1-to-clear status bits so the level-triggered
 * aggregate line deasserts before the IRQ is re-armed. The S2MM IOC bit is
 * the authoritative per-channel completion signal -- the engine sets it (in the
 * register block, not DDR) atomically with the completion -- so it drives the
 * done mask directly. Deciding completion by re-reading the DDR descriptor status
 * instead would race the descriptor writeback: a completion could be missed after
 * its one-shot IOC has already been cleared, leaving the channel to time out even
 * though its data transferred. */
static void scan_channel_irqs(volatile uint8_t *r, uint32_t *done_mask,
                              uint32_t *err_mask)
{
  for (int i = 0; i < NUM_CH; i++) {
    int ch = i + 1;
    uint32_t msr = reg_r(r, MM2S_CH_BASE(ch) + CH_SR);
    uint32_t ssr = reg_r(r, S2MM_CH_BASE(ch) + CH_SR);
    if (ssr & CH_SR_IOC_IRQ)
      *done_mask |= (1u << i);
    if ((msr | ssr) & CH_SR_ERR_IRQ)
      *err_mask |= (1u << i);
    if (msr & CH_SR_IRQ_ALL)
      reg_w(r, MM2S_CH_BASE(ch) + CH_SR, msr & CH_SR_IRQ_ALL);
    if (ssr & CH_SR_IRQ_ALL)
      reg_w(r, S2MM_CH_BASE(ch) + CH_SR, ssr & CH_SR_IRQ_ALL);
  }
}

/* --------------------------------------------------------------------- main -- */

int main(void)
{
  printf("dma-irq: %d-channel prebuffered MCDMA transfer, completion via pl-irq\n\n",
         NUM_CH);

  /* 1. pl-irq node, control window, DMA memory ----------------------------- */
  int irq_fd = open_irq_dev();
  if (irq_fd < 0)
    return EXIT_FAILURE;

  int reg_fd = -1;
  volatile uint8_t *r = map_control_window(&reg_fd);
  if (!r)
    return EXIT_FAILURE;

  int buf_fd = open(UDMABUF_DEV, O_RDWR);
  if (buf_fd < 0) {
    fprintf(stderr, "open %s: %s\n", UDMABUF_DEV, strerror(errno));
    if (errno == ENOENT)
      fprintf(stderr, "  Is u-dma-buf loaded with a '%s' region?\n", UDMABUF_NAME);
    return EXIT_FAILURE;
  }

  uint64_t region_phys = 0, region_size = 0;
  if (sysfs_read_num(UDMABUF_SYS "/phys_addr", &region_phys) ||
      sysfs_read_num(UDMABUF_SYS "/size", &region_size)) {
    fprintf(stderr, "could not read u-dma-buf phys_addr/size\n");
    return EXIT_FAILURE;
  }
  if (region_size < REGION_BYTES) {
    fprintf(stderr, "%s is %" PRIu64 " bytes, need %d\n",
            UDMABUF_NAME, region_size, REGION_BYTES);
    return EXIT_FAILURE;
  }

  uint8_t *region = mmap(NULL, REGION_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED,
                         buf_fd, 0);
  if (region == MAP_FAILED) {
    fprintf(stderr, "mmap %s: %s\n", UDMABUF_DEV, strerror(errno));
    return EXIT_FAILURE;
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

  /* 2. Fill patterns, clear destinations, build descriptors, flush once ----- */
  for (int i = 0; i < NUM_CH; i++) {
    uint32_t *s = (uint32_t *)src[i];
    for (int w = 0; w < BUF_WORDS; w++)
      s[w] = (uint32_t)((i << 24) | (w & 0x00FFFFFF));
    memset(dst[i], 0, BUF_BYTES);
    build_desc(&mm2s_desc[i], mm2s_desc_phys + i * DESC_ALIGN, src_phys[i], BUF_BYTES);
    build_desc(&s2mm_desc[i], s2mm_desc_phys + i * DESC_ALIGN, dst_phys[i], BUF_BYTES);
  }
  if (udmabuf_sync("sync_for_device", 0, REGION_BYTES))
    return EXIT_FAILURE;

  /* 3. Reset, arm every channel with interrupts enabled, start S2MM --------- */
  reset_direction(r, S2MM_CTRL);
  reset_direction(r, MM2S_CTRL);

  for (int i = 0; i < NUM_CH; i++)
    arm_channel_irq(r, S2MM_CH_BASE(i + 1), S2MM_CHEN, i + 1, s2mm_desc_phys + i * DESC_ALIGN);
  run_direction(r, S2MM_CTRL);
  for (int i = 0; i < NUM_CH; i++)
    trigger_channel(r, S2MM_CH_BASE(i + 1), s2mm_desc_phys + i * DESC_ALIGN);

  for (int i = 0; i < NUM_CH; i++)
    arm_channel_irq(r, MM2S_CH_BASE(i + 1), MM2S_CHEN, i + 1, mm2s_desc_phys + i * DESC_ALIGN);
  run_direction(r, MM2S_CTRL);

  /* 4. Arm the pl-irq interrupt, then start MM2S (the source) --------------- */
  if (irq_arm(irq_fd, 1))
    return EXIT_FAILURE;

  int64_t t_start = now_us();
  for (int i = 0; i < NUM_CH; i++)
    trigger_channel(r, MM2S_CH_BASE(i + 1), mm2s_desc_phys + i * DESC_ALIGN);

  /* 5. Block on the interrupt until every S2MM channel has completed -------- */
  uint32_t all_mask  = (NUM_CH >= 32) ? 0xFFFFFFFFu : ((1u << NUM_CH) - 1);
  uint32_t s2mm_done = 0;
  uint32_t err_seen  = 0;
  int    irq_count = 0;
  double first_latency_ms = -1.0;
  int timed_out = 0;

  while (s2mm_done != all_mask) {
    struct pollfd pfd = { .fd = irq_fd, .events = POLLIN };
    int pr = poll(&pfd, 1, IRQ_TIMEOUT_MS);
    if (pr < 0) {
      if (errno == EINTR)
        continue;
      perror("poll");
      break;
    }
    if (pr == 0) {
      /* No interrupt in the window: take one last authoritative reading (a
       * completion may have raced the timeout) before declaring a stall. */
      scan_channel_irqs(r, &s2mm_done, &err_seen);
      if (s2mm_done != all_mask)
        timed_out = 1;
      break;
    }

    uint32_t events = 0;
    if (read(irq_fd, &events, sizeof(events)) != (ssize_t)sizeof(events)) {
      perror("read pl-irq");
      break;
    }
    if (first_latency_ms < 0.0)
      first_latency_ms = (now_us() - t_start) / 1000.0;
    irq_count++;

    /* Doorbell: read the authoritative per-channel status, then clear it so the
     * level line deasserts. */
    scan_channel_irqs(r, &s2mm_done, &err_seen);

    /* Re-arm the interrupt for the remaining completions. */
    if (s2mm_done != all_mask && irq_arm(irq_fd, 1))
      break;
  }

  /* 6. Invalidate the whole region and verify the byte-for-byte round trip -- */
  udmabuf_sync("sync_for_cpu", 0, REGION_BYTES);

  int failures = 0;
  for (int i = 0; i < NUM_CH; i++) {
    int cmplt = (s2mm_done >> i) & 1;
    int err   = (err_seen  >> i) & 1;
    uint32_t got_len = s2mm_desc[i].status & DESC_STAT_LEN_MASK;
    int mismatch = memcmp(src[i], dst[i], BUF_BYTES) != 0;
    int short_len = got_len != BUF_BYTES;
    if (!cmplt || mismatch || short_len || err)
      failures++;
    printf("  ch%d  %s  received %u/%d bytes%s%s\n", i,
           (!cmplt || mismatch || short_len || err) ? "FAIL" : "ok  ",
           got_len, BUF_BYTES,
           !cmplt ? "  (no completion)" : (mismatch ? "  (data mismatch)" : ""),
           err ? "  (error irq)" : "");
  }

  if (timed_out)
    printf("\ntimeout: no interrupt within %d ms; %d channel(s) incomplete\n",
           IRQ_TIMEOUT_MS, failures);
  else
    printf("\ninterrupts: %d;  first-completion latency %.3f ms\n",
           irq_count, first_latency_ms < 0.0 ? 0.0 : first_latency_ms);

  /* Leave the engine clean. */
  irq_arm(irq_fd, 0);
  reset_direction(r, S2MM_CTRL);
  reset_direction(r, MM2S_CTRL);

  munmap(region, REGION_BYTES);
  close(buf_fd);
  munmap((void *)r, MCDMA_WIN_BYTES);
  close(reg_fd);
  close(irq_fd);

  if (failures || timed_out) {
    printf("FAILED: %d channel(s) did not complete via interrupt\n",
           failures ? failures : NUM_CH);
    return EXIT_FAILURE;
  }
  printf("All channels completed and round-tripped (interrupt-driven).\n");
  return EXIT_SUCCESS;
}
