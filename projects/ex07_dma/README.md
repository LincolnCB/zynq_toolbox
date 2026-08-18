***Updated 2026-08-18***

# Example 07: DDR-Backed FIFO Buffers via MCDMA

Example 07 builds a complete DMA data path between the PS (DDR) and the PL and uses it
to give a set of shallow PL FIFOs a large backing store in DDR. The PS preloads long
buffers into DDR ahead of time, an AXI MCDMA engine feeds them into on-chip FIFOs on
demand, and drains PL-produced data back to DDR far faster than the PS could move it
register-by-register. Four MM2S and four S2MM channels run independently, each bound to
its own FIFO and addressed by `TDEST`.

The project introduces the following tools and concepts:
- Driving an AXI MCDMA with independent per-channel scatter-gather rings
- Using DDR as a large FIFO backing store (the "prebuffered" playback/capture model)
- Physically contiguous DMA buffers with `u-dma-buf` plus explicit cache sync
- Non-root MCDMA register access via a `pl-reg` node
- `TDEST` routing and `TLAST` packet semantics across a demux -> FIFO -> mux datapath
- A custom AXI4-Stream packet round-robin mux core

> Status (working): the `per_channel` datapath round-trips all four channels
> byte-for-byte on hardware, without root -- `mcdma-loopback` passes for every channel
> and any subset. What remains is downstream work built on this foundation: a
> programmable-rate PL traffic generator, the UIO interrupt path, and the measurements
> table (see [What's left](#whats-left)).

## Why this example exists

Each item below is an open question in the parent project that this example closes out:

1. Is the Linux MCDMA path usable? Resolved: userspace register control works.
   `mcdma-loopback` drives the MCDMA over a `pl-reg`-mapped window and round-trips data,
   so the parent project can proceed without depending on the lightly-used dmaengine
   MCDMA driver (`drivers/dma/xilinx/xilinx_dma.c`, `device_prep_slave_sg` only).
2. What does MCDMA cost in LUTs? Build at 4+4 and extrapolate to 8+8; the parent
   design is ~60% LUT-utilized and this decides MCDMA vs. eight separate `axi_dma`.
   (pending measurement)
3. What is the worst-case service latency? Measure how long a FIFO can go
   unserviced under load. (pending the traffic-gen core + UIO path)
4. Does the coherency handling work? Resolved: a single `sync_for_device` before
   each run is load-bearing; skipping it reproduces silent corruption (see hardware
   step 3).
5. What does underrun/overflow look like from software? (pending fault injection)

Goal-wise, the point is independent channels -- several DMA regions in flight at once,
each bound to its own FIFO, independently startable and running at unrelated rates --
not raw throughput. The channel count is one Tcl parameter (`num_ch`), so scaling for
the LUT-cost measurement is a one-line change.

## Block design

`block_design.tcl` stands up the MCDMA and a selectable AXI4-Stream datapath, all
clocked at 100 MHz off `FCLK_CLK0`. The channel count is the Tcl parameter `num_ch`
(default 4).

- PS7 with HP0 enabled (the 64-bit path to DDR, carrying both payload and SG
  descriptor fetches) and GP0 for the MCDMA `S_AXI_LITE` control window.
- `axi_mcdma` with `num_ch` MM2S + `num_ch` S2MM channels, scatter-gather enabled
  (mandatory), 64-bit memory-map width (matches HP0 -- do not run HP0 in 32-bit mode),
  and the buffer-length register widened to 23 bits so a multi-MB transfer is one
  descriptor, not a 16 KB-capped chain. The AXIS stream width is 32 bits (read-only /
  derived on this IP).
- Two `smartconnect`s: one for GP0 -> control, one aggregating the MCDMA's three
  memory masters (MM2S, S2MM, SG) onto `S_AXI_HP0`. Addresses are assigned explicitly
  with `addr` (preferred over `auto_connect_axi`, per repo convention).
- `xlconcat` feeding the `2*num_ch` per-channel interrupts into `IRQ_F2P`
  (`IRQ_F2P[0:7]` = GIC IDs 61-68, device tree `<0 29 4>`..`<0 36 4>`).

The `datapath` parameter selects the stream topology between MM2S and S2MM:

- `loopback` -- a single `TDEST`-preserving elastic FIFO looping MM2S straight back
  into S2MM. Minimal PL; validates the MCDMA/HP0/interrupt path with the least logic.
  Kept for regression.
- `per_channel` (default) -- the structure the parent project needs:

  ```
  M_AXIS_MM2S -> mm2s_demux -> dac_fifo[i] -> (rate-gen core, TODO) -> adc_fifo[i] -> s2mm_mux -> S_AXIS_S2MM
                 (axis_switch,                                                        (axis_pkt_rr_mux,
                  1 -> num_ch by TDEST)                                                num_ch -> 1)
  ```

  Each channel gets its own DAC and ADC FIFO, mirroring rev_d_shim (where a SPI core
  sits between them). Today the DAC->ADC gap is a plain wire; the programmable-rate
  traffic-gen core drops in there later. `TDEST == i` is preserved end to end, so MCDMA
  S2MM routes each channel's data back to itself.

The `num_ch -> 1` recombine is the custom core
[`cores/base/axis_pkt_rr_mux`](cores/base/axis_pkt_rr_mux/axis_pkt_rr_mux.v): it grants
one input, holds it through `TLAST`, then advances round-robin, so packets are never
interleaved onto the single S2MM stream and no channel starves. It replaced a stock
`axis_switch`, which could not be forced to arbitrate on packet boundaries (see
[Design notes](#design-notes)). The core has a cocotb testbench under its `tests/`.

## Software

`software/mcdma-loopback/mcdma-loopback.c` implements the prebuffered model, which
is the parent project's actual usage and the easy one: software is not in the loop
during a transfer, so scheduling jitter cannot cause an underrun. It:

1. maps the MCDMA control window (`/dev/mcdma` via `pl-reg`, else `/dev/mem`),
2. allocates one `u-dma-buf` region and carves it into an SG descriptor area plus a
   src/dst payload pair per channel,
3. fills each src with a distinct pattern (`(ch<<24)|word`) and builds one MM2S and one
   S2MM descriptor per channel,
4. `sync_for_device` once (flush to DDR), starts every channel, polls each S2MM
   descriptor for completion, `sync_for_cpu`, and verifies the byte-exact round trip.

Pass channel indices to run a subset (`mcdma-loopback 1`, `mcdma-loopback 0 2`); no args
runs all. The MCDMA register map and SG descriptor layout follow mainline
`xilinx_dma.c` -- note that MCDMA's descriptor `control` word is at `0x14` (not the
AXI-DMA `0x18`) and Run/Stop must be set in both the per-channel and the common
control register. With the widened length register and a contiguous allocation a whole
channel is one descriptor; the code handles a chain anyway since the parent project
will need one.

Non-root access: the register window is non-root via `pl-reg`. `u-dma-buf` exposes
two root-owned interfaces the program touches -- the `/dev/udmabuf0` mmap node (0600)
and the sysfs cache-sync controls `/sys/class/u-dma-buf/udmabuf0/sync_*` (0664) -- with
no mode knob; miss the sysfs controls and `mmap` still succeeds but the first
`sync_for_device` fails `EACCES`. The project's top-level `boot_script.sh` `chmod`s both
to 0666 at boot (installed as an `/etc/init.d` service by
`scripts/petalinux/boot_script.sh`; this rootfs has no udev), so the whole demo runs as
an ordinary user.

Cache coherency: HP ports are not coherent with L1/L2. Prebuffered mode needs only
one `sync_for_device` per buffer before the run and one `sync_for_cpu` after -- no
per-chunk sync -- using a cached mapping so filling multi-MB patterns stays fast.

Flow control is handled entirely by `TREADY` backpressure: a full downstream FIFO
stalls the MCDMA channel mid-descriptor, so DMA overrun of a PL FIFO is not possible and
no `almost_full`/fill-count signalling is needed. `software/xilinx-dma-test/` is
superseded (it drove a plain `axi_dma` in direct-register mode) and kept only as a
register-model reference.

## Device tree

`cfg/.../petalinux/<ver>/device_tree.dtsi` declares two things:

- a `reserved-memory` region (4 MiB at `0x30000000`) that `u-dma-buf` claims as
  `/dev/udmabuf0`. The base and size must both be 4 MiB-aligned or
  `of_reserved_mem_device_init` fails `-22` on 32-bit ARM.
- a `compatible` override on the MCDMA node to a private
  `zynq-toolbox,mcdma-userspace` string, so no in-kernel driver matches it and `pl-reg`
  claims it deterministically as `/dev/mcdma` (rather than relying on the `xilinx_dma`
  probe failing -- PetaLinux otherwise tags a standalone MCDMA as `xlnx,eth-dma`).

## Build integration

A normal `make PROJECT=ex07_dma` produces an SD image where the block design (bitstream
+ `.xsa`) contains the MCDMA and the selected `datapath`, `u-dma-buf` is built
out-of-tree from `kernel_modules/` and autoloaded, the `boot_script.sh` chmod service is
installed (by `scripts/petalinux/boot_script.sh`, guarded by
`scripts/check/boot_script.sh`), and `mcdma-loopback` is cross-compiled into the rootfs.

## Trying it on hardware

After `make PROJECT=ex07_dma`, write the SD image, boot, and log in.

1. Confirm the `u-dma-buf` region and the `pl-reg` window came up:

```sh
cat /sys/class/u-dma-buf/udmabuf0/size   # >= REGION_BYTES; the DT reserves 4 MiB
ls -l /dev/mcdma                         # crw-rw-rw- (non-root, via pl-reg)
```

If `/dev/udmabuf0` is missing, the `reserved-memory` node didn't take (CMA failures are
quiet -- check `dmesg`). If `/dev/mcdma` is missing, the `compatible` override didn't
apply and the MCDMA bound to a kernel driver; the program still runs via its `/dev/mem`
fallback under `sudo`.

2. Run the loopback (no args runs all channels; pass indices for a subset):

```
petalinux:~$ mcdma-loopback
mcdma-loopback: 4-channel prebuffered MCDMA loopback via u-dma-buf
running channels: 0 1 2 3

MCDMA control: /dev/mcdma (pl-reg, no root)
u-dma-buf udmabuf0: phys 0x30000000, 20480 bytes used of 4194304

  ch0  ok    received 2048/2048 bytes
  ch1  ok    received 2048/2048 bytes
  ch2  ok    received 2048/2048 bytes
  ch3  ok    received 2048/2048 bytes

All channels round-tripped.
```

On timeout the `dump_status` output shows per-channel `MM2S`/`S2MM` `SR` (bit 0 =
HALTED), `CH_ERR`, each descriptor's status from DDR, and `src[0..3]` vs `dst[0..3]`: an
all-zero `dst` is starvation, another channel's high byte is a misroute. If transfers
fail immediately with no data, suspect the TrustZone `DECERR` gotcha. If you get
`Permission denied`, the boot script didn't run -- check `/etc/init.d/boot-script` and
fall back to `sudo mcdma-loopback`.

3. (Optional) prove the cache sync is real. Comment out the `sync_for_device` call
in `mcdma-loopback.c`, rebuild, and re-run: you should get intermittent mismatches as
data sits in CPU cache instead of DDR. Restore it afterward.

## What's left

The DMA foundation works; the remaining items build the measurement and stress harness
on top of it.

- [ ] Programmable-rate traffic generator/checker core between the per-channel DAC
      and ADC FIFOs (replaces the placeholder wire). This is what lets channels run at
      deliberately unrelated rates and be paused independently.
- [ ] Independent-rate and mid-run-pause tests once that core exists.
- [ ] Fault injection: deliberate underrun (start the PL consumer before the DMA)
      and missed-flush corruption; characterize what software can detect.
- [ ] MCDMA completion/error interrupts via UIO (`generic-uio`): aggregate the
      per-channel IRQs, block with `read()`/`poll()` on `/dev/uioN`, and use it for the
      completion-latency number and to see underrun/overflow. Keep the happy path
      polled. In the parent project, fold DMA errors into `hw_manager`'s single
      error-alert IRQ rather than standing up a parallel UIO.
- [ ] Measurements table: LUT/FF/BRAM at 2+2 and 4+4 (MCDMA vs. 8x `axi_dma`),
      sustained aggregate MB/s, max FIFO-service gap, interrupt latency, and descriptor
      overhead vs. chunk size.
- [ ] Compare the dmaengine path (option A: `CONFIG_XILINX_DMA` +
      `dmaengine_prep_slave_sg`) against direct register control; note it pairs
      awkwardly with `u-dma-buf` (wants `dma_alloc_coherent`).
- [ ] (stretch) Mode 2 streaming: append descriptors ahead of the ring tail during
      a run. Works with MCDMA as-is (no cyclic mode); attempt only after mode 1.

Done so far: the MCDMA block design (`num_ch`-per-direction, GP0 control, HP0 memory +
SG, per-channel interrupts, `datapath` selector); the `per_channel` demux/FIFO/custom-mux
datapath; `u-dma-buf` allocation + single-sync coherency; non-root access via `pl-reg` +
the boot-time chmod; and the prebuffered round-trip demo, validated on hardware at 4+4.

## Design notes

Two `s2mm_mux` bugs surfaced while bringing up `per_channel`; both cost real debugging
time and are easy to hit again:

- `axis_switch` TDEST windows take hex. The demux's per-MI `BASETDEST`/`HIGHTDEST`
  are `bitString` params: pass `[format 0x%08X $i]`, not a bare integer, or the derived
  `C_M_AXIS_*TDEST_ARRAY` modelparam rejects any value needing more than one bit (0 and
  1 slip through, which hid it until `num_ch >= 3`). A single MI also defaults to the
  TDEST window `[0,0]` and silently drops every higher channel, so a mux MI's window
  must span `[0, num_ch-1]`.
- S2MM recombine needs packet-atomic arbitration. A stock `axis_switch`
  (`ROUTING_MODE 0`) re-arbitrates per beat, interleaving channels onto the single S2MM
  stream; MCDMA latches `TDEST` at start-of-packet and needs each packet contiguous, so
  the mix lands on one channel and the rest starve. `ARB_ON_TLAST` does not stick on
  that IP in `ROUTING_MODE 0` (it reads back 0), so the fix is the custom
  `axis_pkt_rr_mux` -- grant one input, hold through `TLAST`, advance round-robin.
  Confirmed on hardware: all four channels round-trip byte-exact.

Other things worth knowing:

- Flow control is `TREADY`, not fill-count. A full downstream FIFO stalls the MCDMA
  channel mid-descriptor; DMA overrun of a PL FIFO is not possible. Assert `TLAST` only
  at end-of-capture (per-sample `TLAST` makes tiny one-descriptor packets).
- TrustZone: PS peripherals default to secure; accesses with `AxPROT[1]=1` return
  `DECERR`. Check this first if transfers fail immediately.
- Don't use 32-bit HP mode, and remember the HP interface may reorder reads/writes
  (MCDMA handles it; a custom PL master must).

## Reference notes

- [ex04](../ex04_interrupts/README.md) -- delivering PL interrupts to userspace; the
  DMA completion interrupts reuse this.
- [ex05](../ex05_device_driver/README.md) -- reaching PL registers via a non-root misc
  driver; the MCDMA control window reuses this pattern.
- `PROJECT_BRIEF.md` -- the parent project this example de-risks, including the
  reasoning behind choosing MCDMA and the prebuffered model.
- UG585 (Zynq-7000 TRM), AXI_HP Interfaces chapter -- port behavior, FIFO depths,
  reordering, and the performance optimization summary.
- PG288 -- AXI MCDMA product guide. PG021 -- AXI DMA, for comparison.

---

Previous: [Example 05: Device Driver](../ex05_device_driver/README.md)
