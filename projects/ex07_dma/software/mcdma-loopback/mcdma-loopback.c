/* mcdma-loopback -- prebuffered AXI MCDMA loopback test using u-dma-buf.
 *
 * This is the ex07 successor to xilinx-dma-test.c. That program drove a plain
 * axi_dma in *direct register* mode (MM2S_SRC_ADDRESS / TRNSFR_LENGTH /
 * S2MM_DST_ADDRESS ...) over /dev/mem at hardcoded raw physical addresses. None
 * of that applies here: the block design now uses an AXI *MCDMA*, which is
 * scatter-gather only (no direct mode) and has a multichannel register map. So
 * this program is a clean rewrite around the model ex07 actually needs:
 *
 *   - contiguous DMA memory from u-dma-buf (physically contiguous, physical
 *     address readable from sysfs, cached mapping with an explicit one-shot
 *     cache sync), instead of /dev/mem + guessed physical addresses,
 *   - a scatter-gather descriptor ring built in that memory,
 *   - the MCDMA "prebuffered" model: fill everything, sync once, start all
 *     channels, then just wait for completion -- software is not in the loop
 *     during the transfer,
 *   - per-channel independence: each MM2S channel i loops back to S2MM channel i
 *     by TDEST (see block_design.tcl, datapath = loopback).
 *
 * Flow (per the prebuffered model):
 *   1. map the MCDMA control window (pl-reg /dev node preferred, /dev/mem
 *      fallback),
 *   2. allocate one u-dma-buf region and carve it into a descriptor area plus a
 *      src/dst payload pair per channel,
 *   3. fill each src with a distinct pattern, clear each dst, build one MM2S and
 *      one S2MM descriptor per channel,
 *   4. sync_for_device once (flush src + descriptors to DDR),
 *   5. start S2MM then MM2S on every channel,
 *   6. poll each descriptor's completion bit until all finish (or time out),
 *   7. sync_for_cpu once (invalidate) and verify dst == src byte-for-byte.
 *
 * The MCDMA register map, the SG descriptor layout (note: `control` is at 0x14,
 * not the AXI-DMA 0x18), the SOF/EOF bits (31/30 for MCDMA), and the start
 * sequence (per-channel + common Run/Stop) all match mainline
 * drivers/dma/xilinx/xilinx_dma.c, and this program round-trips 2+2 channels on
 * hardware. MM2S drives TDEST from the channel a BD is queued on, so no TDEST
 * field is set in the descriptor.
 *
 * Prerequisites on the target (see this project's README and device tree):
 *   - u-dma-buf loaded with a region named UDMABUF_NAME (device tree
 *     reserved-memory node, autoloaded), big enough for REGION_BYTES,
 *   - the MCDMA reachable as a pl-reg node (/dev/mcdma, non-root) or via /dev/mem.
 *     The register window is non-root, but the u-dma-buf buffer node is root-owned
 *     (this rootfs has no udev), so run under sudo until a boot-time chmod is added.
 *
 * Run with:  sudo mcdma-loopback
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
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

/* ------------------------------------------------------------------ config -- */

#define NUM_CH          2               /* channels per direction (match num_ch) */
#define BUF_WORDS       512             /* 32-bit words per channel payload      */
#define BUF_BYTES       (BUF_WORDS * 4)

#define DESC_BYTES      64              /* MCDMA SG descriptor size               */
#define DESC_ALIGN      64
#define DESC_AREA_BYTES 0x1000          /* room for all descriptors, 4 KiB       */

/* One u-dma-buf region holds the descriptors then the per-channel payloads. */
#define PAYLOAD_OFFSET  DESC_AREA_BYTES
#define REGION_BYTES    (PAYLOAD_OFFSET + NUM_CH * 2 * BUF_BYTES)

#define UDMABUF_NAME    "udmabuf0"
#define UDMABUF_DEV     "/dev/" UDMABUF_NAME
#define UDMABUF_SYS     "/sys/class/u-dma-buf/" UDMABUF_NAME

#define MCDMA_DEV       "/dev/mcdma"    /* pl-reg node, if bound (non-root)       */
#define MCDMA_MEM_BASE  0x40400000UL    /* /dev/mem fallback (block_design.tcl)   */
#define MCDMA_WIN_BYTES 0x10000UL       /* control-window size (64K)              */

#define POLL_TIMEOUT_US 1000000         /* 1 s of polling before giving up        */

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

/* Per-channel register blocks. Hardware indexes channels from 0 (== ch-1 here);
 * xilinx_dma.c uses CHAN_CR_OFFSET(x) = 0x40 + x*0x40 relative to the direction's
 * control base (0x000 for MM2S, 0x500 for S2MM). */
#define MM2S_CH_BASE(n) (0x040 + ((n) - 1) * 0x40)
#define S2MM_CH_BASE(n) (0x540 + ((n) - 1) * 0x40)
#define CH_CR           0x00            /* channel control (bit0 RS)              */
#define CH_SR           0x04            /* channel status                         */
#define CH_CURDESC      0x08
#define CH_CURDESC_MSB  0x0C
#define CH_TAILDESC     0x10
#define CH_TAILDESC_MSB 0x14

/* Run/Stop (bit0) and soft-reset (bit2). MCDMA needs RS set BOTH in each
 * channel's CH_CR *and* in the direction's common control register; reset lives
 * in the common control register only. Common status bit0 = HALTED. */
#define CR_RS           0x00000001
#define CR_RESET        0x00000004
#define SR_HALTED       0x00000001

/* SG descriptor control/status bit fields (per xilinx_dma.c: MCDMA SOP/EOP are
 * bits 31/30, unlike plain AXI-DMA which uses 27/26). */
#define DESC_CTRL_SOF   0x80000000      /* start-of-packet (BIT 31)               */
#define DESC_CTRL_EOF   0x40000000      /* end-of-packet   (BIT 30)               */
#define DESC_CTRL_LEN_MASK 0x03FFFFFF   /* buffer length in the low bits          */
#define DESC_STAT_CMPLT 0x80000000      /* descriptor completed (BIT 31)          */
#define DESC_STAT_LEN_MASK 0x03FFFFFF

/* MCDMA hardware descriptor (struct xilinx_aximcdma_desc_hw). NOTE the layout
 * differs from the AXI-DMA BD: `control` is at 0x14 and `status` at 0x18 (the
 * AXI-DMA BD puts them at 0x18/0x1C). 64 bytes, 64-byte aligned. */
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

/* Read an integer from a u-dma-buf sysfs attribute. The values are inconsistent:
 * phys_addr is hex with a 0x prefix, size is plain decimal. strtoull(base=0)
 * handles both (0x -> hex, otherwise decimal). */
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

/* Trigger a u-dma-buf cache sync over [offset, offset+size) via sysfs. `attr` is
 * "sync_for_device" (flush before DMA) or "sync_for_cpu" (invalidate after).
 * The combined write format is documented in the u-dma-buf README. */
static int udmabuf_sync(const char *attr, uint64_t offset, uint64_t size)
{
  char path[128];
  snprintf(path, sizeof(path), UDMABUF_SYS "/%s", attr);

  int fd = open(path, O_WRONLY);
  if (fd < 0) {
    fprintf(stderr, "open %s: %s\n", path, strerror(errno));
    return -1;
  }
  /* low word: (size & ~0xF) | (direction << 2) | enable; direction 0 = bidir. */
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

/* Prefer the non-root pl-reg node; fall back to /dev/mem. */
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

/* ------------------------------------------------------------- descriptors -- */

/* Build one single-buffer descriptor: covers [buf_phys, buf_phys+len), marked
 * start- and end-of-packet, next pointer looping to itself (single-entry ring).
 * MM2S drives TDEST from the channel the BD is queued on, so no TDEST field is
 * needed here. */
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

/* Arm one channel: program its current descriptor, enable it in CHEN, and set
 * the per-channel Run/Stop bit. The direction's common RS (run_direction) and
 * the tail-descriptor write (trigger_channel) happen after all channels are
 * armed. This mirrors xilinx_mcdma_start_transfer(). */
static void arm_channel(volatile uint8_t *r, uint32_t ch_base, uint32_t chen,
                        int ch, uint64_t desc_phys)
{
  reg_w(r, ch_base + CH_CURDESC,     (uint32_t)desc_phys);
  reg_w(r, ch_base + CH_CURDESC_MSB, (uint32_t)(desc_phys >> 32));
  reg_w(r, chen, reg_r(r, chen) | (1u << (ch - 1)));            /* enable ch     */
  reg_w(r, ch_base + CH_CR, reg_r(r, ch_base + CH_CR) | CR_RS); /* per-ch run    */
}

/* Write the tail descriptor -- this is what actually starts the BD fetch. */
static void trigger_channel(volatile uint8_t *r, uint32_t ch_base, uint64_t desc_phys)
{
  reg_w(r, ch_base + CH_TAILDESC,     (uint32_t)desc_phys);
  reg_w(r, ch_base + CH_TAILDESC_MSB, (uint32_t)(desc_phys >> 32));
}

/* Set the direction's common Run/Stop bit and wait for it to leave the halted
 * state. `ctrl` is MM2S_CTRL or S2MM_CTRL; the status register is ctrl + 4. */
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

/* Soft-reset a whole direction via its common control register (bit 2). */
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

/* Dump the engine state, for when a transfer does not complete. */
static void dump_status(volatile uint8_t *r)
{
  fprintf(stderr, "  MM2S SR=0x%08x CH_ERR=0x%08x   S2MM SR=0x%08x CH_ERR=0x%08x\n",
          reg_r(r, MM2S_SR), reg_r(r, MM2S_CH_ERR),
          reg_r(r, S2MM_SR), reg_r(r, S2MM_CH_ERR));
  for (int i = 0; i < NUM_CH; i++) {
    int ch = i + 1;
    fprintf(stderr, "  ch%d  MM2S CR=0x%08x SR=0x%08x   S2MM CR=0x%08x SR=0x%08x\n", i,
            reg_r(r, MM2S_CH_BASE(ch) + CH_CR), reg_r(r, MM2S_CH_BASE(ch) + CH_SR),
            reg_r(r, S2MM_CH_BASE(ch) + CH_CR), reg_r(r, S2MM_CH_BASE(ch) + CH_SR));
  }
}

/* --------------------------------------------------------------------- main -- */

int main(void)
{
  printf("mcdma-loopback: %d-channel prebuffered MCDMA loopback via u-dma-buf\n\n",
         NUM_CH);

  /* 1. Control window ------------------------------------------------------- */
  int reg_fd = -1;
  volatile uint8_t *r = map_control_window(&reg_fd);
  if (!r)
    return EXIT_FAILURE;

  /* 2. DMA memory ----------------------------------------------------------- */
  int buf_fd = open(UDMABUF_DEV, O_RDWR);   /* no O_SYNC: keep the mapping cached */
  if (buf_fd < 0) {
    fprintf(stderr, "open %s: %s\n", UDMABUF_DEV, strerror(errno));
    if (errno == ENOENT)
      fprintf(stderr, "  Is u-dma-buf loaded with a '%s' region? (dmesg | grep u-dma-buf)\n",
              UDMABUF_NAME);
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

  /* Sub-region layout inside the single region. */
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

  /* 3. Fill patterns, clear destinations, build descriptors ----------------- */
  for (int i = 0; i < NUM_CH; i++) {
    uint32_t *s = (uint32_t *)src[i];
    for (int w = 0; w < BUF_WORDS; w++)
      s[w] = (uint32_t)((i << 24) | (w & 0x00FFFFFF));   /* per-channel pattern   */
    memset(dst[i], 0, BUF_BYTES);

    build_desc(&mm2s_desc[i], mm2s_desc_phys + i * DESC_ALIGN,
               src_phys[i], BUF_BYTES);
    build_desc(&s2mm_desc[i], s2mm_desc_phys + i * DESC_ALIGN,
               dst_phys[i], BUF_BYTES);
  }

  /* 4. One flush of the whole region to DDR before starting ----------------- */
  if (udmabuf_sync("sync_for_device", 0, REGION_BYTES))
    return EXIT_FAILURE;

  /* 5. Reset both directions, arm all channels, set the common Run/Stop, then
   *    trigger. S2MM (receiver) is brought up before MM2S (source). ---------- */
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

  /* 6. Poll every S2MM descriptor for completion ---------------------------- */
  int64_t deadline = now_us() + POLL_TIMEOUT_US;
  int pending = NUM_CH;
  while (pending > 0 && now_us() < deadline) {
    /* Descriptor status lives in DDR; invalidate before each peek. */
    udmabuf_sync("sync_for_cpu", NUM_CH * DESC_ALIGN, NUM_CH * DESC_ALIGN);
    pending = 0;
    for (int i = 0; i < NUM_CH; i++)
      if (!(s2mm_desc[i].status & DESC_STAT_CMPLT))
        pending++;
  }
  if (pending > 0) {
    fprintf(stderr, "timeout: %d S2MM channel(s) did not complete\n", pending);
    dump_status(r);
  }

  /* 7. Invalidate the payloads and verify byte-for-byte --------------------- */
  udmabuf_sync("sync_for_cpu", PAYLOAD_OFFSET, NUM_CH * 2 * BUF_BYTES);

  int failures = 0;
  for (int i = 0; i < NUM_CH; i++) {
    uint32_t got_len = s2mm_desc[i].status & DESC_STAT_LEN_MASK;
    int mismatch = memcmp(src[i], dst[i], BUF_BYTES) != 0;
    int short_len = got_len != BUF_BYTES;
    if (mismatch || short_len)
      failures++;
    printf("  ch%d  %s  received %u/%d bytes%s\n", i,
           (mismatch || short_len) ? "FAIL" : "ok  ",
           got_len, BUF_BYTES,
           mismatch ? "  (data mismatch)" : "");
  }
  printf("\n");

  munmap(region, REGION_BYTES);
  close(buf_fd);
  munmap((void *)r, MCDMA_WIN_BYTES);
  close(reg_fd);

  if (failures) {
    printf("FAILED: %d channel(s) did not round-trip\n", failures);
    return EXIT_FAILURE;
  }
  printf("All channels round-tripped.\n");
  return EXIT_SUCCESS;
}
