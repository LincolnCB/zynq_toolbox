***Updated 2026-08-12***

# Example 07: DDR-Backed FIFO Buffers via MCDMA

Example 07 builds a complete DMA data path between the PS (DDR memory) and the PL,
and uses it to give a set of shallow PL FIFOs a large backing store in DDR. The PS
preloads long buffers into DDR ahead of time; the DMA engine feeds them into on-chip
FIFOs on demand, and drains PL-produced data back out to DDR far faster than the PS
could read it register-by-register.

This is a **deliberately small, isolated testbed** for the DMA approach adopted in the
parent project (see `PROJECT_BRIEF.md`). That system needs 8 MM2S + 8 S2MM channels
feeding sixteen per-board FIFOs. Getting that wrong on real hardware means a
sequence-halting fault and a manual recovery, so the point of this example is to learn
the mechanics, measure the costs, and hit the failure modes somewhere harmless first.

> **Status:** the mode-1 (prebuffered) 2+2 loopback works end to end on hardware --
> the block design builds, `u-dma-buf` and the `pl-reg`-bound MCDMA come up, and
> `mcdma-loopback` round-trips both channels byte-for-byte. Sections still marked
> _(planned)_ -- the per-channel datapath, the programmable-rate traffic generator,
> and the measurements -- are the remaining work. See "Trying it on hardware" to run
> it.

## What this example is de-risking

Each item here is an open question in the parent project that this example is meant to
close out. Keep them in view; they are the reason the example exists.

1. **Is the Linux MCDMA path usable?** The dmaengine driver
   (`xlnx,axi-mcdma-1.00.a` in `drivers/dma/xilinx/xilinx_dma.c`) implements only
   `device_prep_slave_sg` -- no cyclic mode -- and is far less exercised than the plain
   `axi_dma` driver. Determine whether to use it or to drive the MCDMA registers
   directly from userspace. See "Two ways to drive it" below.
   **Resolved:** userspace register control works -- `mcdma-loopback` drives the MCDMA
   over a `pl-reg`-mapped register window and round-trips data, so the parent project
   can proceed with option B without depending on the dmaengine MCDMA driver.
2. **What does MCDMA actually cost in LUTs?** Build at 2+2 channels, then rebuild at
   4+4, and extrapolate to 8+8. The parent design is at roughly 60% LUT utilization
   and this number decides whether MCDMA or eight separate `axi_dma` instances is
   viable there.
3. **What is the real worst-case service latency?** Measure how long a FIFO can be
   left unserviced under load. The parent system's margin calculation assumes DMA
   latency is microseconds against a millisecond-scale FIFO drain time; confirm that
   with numbers rather than arithmetic.
4. **Does the coherency handling actually work?** Silent data corruption from a missed
   cache flush is the classic failure here, and it will not show up in a short test.
5. **What does underrun/overflow look like from software?** In the parent system this
   is a hard shutdown. Here it is free to provoke deliberately and characterize.

## Goals

1. **Stand up a full DMA data path.** Move data between PS DDR and the PL over AXI in
   both directions, using an AXI MCDMA engine and the PS high-performance (HP) AXI
   slave port.

2. **Demonstrate multiple genuinely independent channels.** Several DMA regions in
   flight at once, each bound to its own PL FIFO, each independently startable and
   stoppable, running at unrelated rates. This -- not raw throughput -- is the core
   skill the example teaches.

3. **Use DDR as a FIFO extension.** On-chip BRAM FIFOs are small. Backing each with a
   DDR region makes the effective depth as large as the DDR allocation, letting the PS
   preload an entire run ahead of time and stay out of the loop while it plays.

4. **Cover the parts that are easy to get wrong.** Cache coherency, physically
   contiguous allocation, descriptor ring construction, `TDEST` routing, `TLAST`
   semantics, and address-space mapping.

5. **Optimize for clarity.** Small, heavily commented block design and software, so
   each piece can be lifted into a larger project and scaled up.

## Scope: why 2+2 (and optionally 4+4)

Two MM2S and two S2MM channels, feeding four AXI-Stream FIFOs.

Two per direction rather than one, because a single channel per direction proves
nothing about the hard part: `TDEST`/`TID` routing, per-channel descriptor rings, and
independent start/stop are exactly what breaks at scale, and they are invisible in a
1+1 loopback. Not eight per direction yet, because the mechanics are identical and the
resource cost extrapolates -- keep the example readable.

Make the channel count a Tcl parameter in `block_design.tcl` so a 4+4 build is a
one-line change. That is what makes goal 2 above (LUT scaling) cheap to measure.

## Block design plan _(planned)_

- `processing_system7` with **HP0** enabled (the DMA's path to DDR, carrying both
  payload and scatter-gather descriptor fetches) and **GP0** for the MCDMA
  `S_AXI_LITE` control window.
- `axi_mcdma` with `CONFIG.c_num_mm2s_channels {2}` and
  `CONFIG.c_num_s2mm_channels {2}`. Scatter-gather is mandatory on MCDMA; the
  descriptor rings live in DDR and are reached over the same HP path.
- **Memory-map data width 64 bits, stream data width 32 bits.** The 64-bit memory
  side matches the HP port; do not configure HP0 in 32-bit mode. The 32-bit stream
  matches the parent project's FIFO width.
- **Widen the buffer-length register.** Check this value -- if it is left at the
  14-bit default, a single descriptor caps out at 16 KB, which quietly turns a
  one-descriptor transfer into a thousand-descriptor chain. Set it to 23 bits (8 MB)
  or wider.
- Two AXI **smartconnect** instances: one for PS-to-peripheral control, one
  aggregating the MCDMA's memory-mapped masters (MM2S, S2MM, and SG) into `S_AXI_HP0`.
- Explicit `addr` assignments for the MCDMA control window and the HP0 memory window
  (preferred over `auto_connect_axi`, per repo convention).
- `xlconcat` feeding MCDMA per-channel interrupts into `IRQ_F2P`. Note the mapping:
  `IRQ_F2P[0:7]` are GIC IDs 61-68, which appear in the device tree as `<0 29 4>`
  through `<0 36 4>`.
- Four AXIS FIFOs plus the `TDEST` fan-out (MM2S side) and combine (S2MM side). An
  `axis_switch` works; for a fixed map, a small hand-written demux is cheaper and
  easier to read.
- A PL-side traffic generator/checker per read FIFO, with a **programmable rate**, so
  channels can be run at deliberately unrelated rates and paused independently. This
  is what makes goal 2 testable.

**Clock the datapath at 100 MHz.** 64 bits at 100 MHz is 800 MB/s, orders of magnitude
beyond what this example moves, and it keeps timing closure uneventful.

## The DMA-as-FIFO model _(planned)_

There are two operating modes worth building, and they have very different difficulty.
Build the first one; treat the second as an extension.

### Mode 1: prebuffered playback and capture (primary)

The PS allocates a DDR buffer per channel, fills the MM2S buffers with the entire
pattern, builds a descriptor chain covering the whole thing, flushes caches once,
starts all channels, and then does nothing until completion interrupts arrive.

This is the parent project's actual model, and it is much easier than a streaming ring:
**software is not in the loop during the run at all**, so scheduling jitter cannot
cause an underrun. The only failure mode left is running out of aggregate bandwidth,
where the margin is enormous.

With a widened length register and a contiguous allocation, a whole channel's transfer
may be a *single descriptor*. Build the code to handle a chain anyway -- the parent
system will need one -- but expect chains of one to a handful of entries.

### Mode 2: continuous streaming (extension, optional)

Keep appending descriptors ahead of the ring's tail pointer while the transfer runs.
The deadline is not the FIFO drain time but the time to drain everything already
queued, which with a few MB queued is seconds. This works with MCDMA as-is and does
not need cyclic mode.

Only attempt this after mode 1 works end to end.

### Flow control: mostly not your problem

The original plan for this example proposed using FIFO `almost_full` / fill-count
signals as the DMA flow-control mechanism. **This is unnecessary and should not be
built.** AXI-Stream `TREADY` backpressure already does it: when a downstream FIFO is
full, it deasserts `TREADY`, the MCDMA channel stalls mid-descriptor, and it resumes
when space appears. Overrun of a PL FIFO by the DMA is not possible through this path.

What you *do* have to get right:

- **`TLAST` on the S2MM side.** MCDMA closes a descriptor on `TLAST` or when the
  buffer fills. Without `TLAST`, a partial final buffer sits in the engine and never
  completes, and you cannot tell how many bytes actually arrived. Assert `TLAST` at
  the end of a capture. Do *not* assert it per-sample -- that produces tiny packets
  and one descriptor's worth of overhead each.
- **Reading the completed-byte count** from the descriptor status field for partial
  transfers.
- **DDR-side bookkeeping** -- how far the PS has consumed a capture buffer, and how
  far it has filled a playback buffer. This is ordinary ring accounting and only
  matters in mode 2.

## Two ways to drive it _(decided: start with B)_

**A. Linux dmaengine.** Enable `CONFIG_XILINX_DMA`, describe the MCDMA in the device
tree, write a small consumer driver using `dmaengine_prep_slave_sg()`. Idiomatic, and
descriptor management is handled for you. Risk: the MCDMA path in this driver is
comparatively lightly used. Note also that dmaengine wants to own its buffers through
the kernel DMA API, so this route pairs awkwardly with `u-dma-buf` and probably means
`dma_alloc_coherent` in the consumer driver instead.

**B. Userspace register control.** Map the MCDMA control registers via the
`pl-reg`-style misc driver from ex05, allocate buffers with `u-dma-buf`, build
descriptor rings by hand, and program the channel pointers directly. More code and you
own the SG bookkeeping, but it sidesteps the driver-maturity question entirely, makes
every step visible -- which is the point of an example -- and matches how the parent
system already works (mmap once, no syscalls in the loop).

**Start with B.** It is the parent project's preferred direction, it pairs cleanly
with `u-dma-buf`, and understanding the hardware on its own terms is the whole
justification for building an isolated example. Try A afterward and compare; if it
works cleanly it may simplify the parent project, and if it does not, B is already a
demonstrated fallback rather than a panic move.

## Software plan _(planned)_

- **Contiguous buffers via `u-dma-buf`.** The vendored module under
  `examples/kernel_modules/u-dma-buf` is already symlinked into `kernel_modules/`, so
  the standard build auto-discovers and compiles it out-of-tree and autoloads it at
  boot (`kernel_modules.sh` builds every subdirectory of `kernel_modules/` and appends
  `KERNEL_MODULE_AUTOLOAD`). A bare autoload loads the module with no regions, though,
  so the DMA regions still have to be declared -- via `u-dma-buf` device-tree nodes or
  module parameters (`modprobe.d` options) -- to get one `/dev/udmabufN` per channel
  plus one small region for the descriptor rings; read each region's physical address
  from sysfs to program descriptors. `cma=64M` in bootargs is plenty for the example;
  the parent project should move to a `reserved-memory` node so allocation cannot fail
  from fragmentation. Confirm allocations actually succeed -- CMA failures are quiet.
- **Non-root access.** ex05 gets a non-root `/dev` node by setting `misc.mode = 0666`
  on its misc device, deliberately avoiding udev because this rootfs cannot install
  udev rules. `u-dma-buf`'s `/dev/udmabufN` nodes come up root-owned, so matching that
  goal for the buffer nodes is an open item: either `chmod` them from a boot script,
  or accept root for the allocation step while keeping the MCDMA register `mmap`
  non-root through the `pl-reg`-style misc driver (option B below).
- **Cache coherency.** HP ports are not coherent with L1/L2. Because mode 1 is
  prebuffered, a **single sync per buffer before starting** is sufficient; no
  per-chunk synchronization. Use a cached mapping plus `u-dma-buf`'s
  `sync_for_device` / `sync_for_cpu` sysfs controls rather than a non-cached mapping,
  so filling multi-MB patterns from userspace stays fast. Check the exact attribute
  names and `sync_mode` semantics against the vendored version. Then deliberately
  break it -- skip the sync -- and confirm you can reproduce the corruption. Knowing
  what that failure looks like is worth the ten minutes.
- **Demonstration program.** `software/mcdma-loopback/mcdma-loopback.c` is the
  starting point: it allocates one `u-dma-buf` region (declared as a
  `reserved-memory` node in `cfg/.../petalinux/<ver>/device_tree.dtsi`), carves it
  into a descriptor area plus a src/dst pair per channel, preloads distinct patterns,
  syncs once, builds an SG descriptor ring, starts all channels, polls for completion,
  and verifies the byte-exact round trip. The MCDMA register/descriptor specifics are
  flagged `VALIDATE` in-file. It reaches the MCDMA control window through a pl-reg node
  (`/dev/mcdma`, non-root) if one is bound, else `/dev/mem` (root). Next steps: run the
  channels at deliberately different rates and pause one mid-run (needs the
  `per_channel` datapath + rate-gen core).
- **Fault injection.** Starve an MM2S channel (start the PL consumer before the DMA)
  and confirm what the PL sees and what software can detect. This directly informs
  the parent system's watchdog design.
- `software/xilinx-dma-test/xilinx-dma-test.c` is **superseded** (it drove a plain
  `axi_dma` in direct-register mode over `/dev/mem` at hardcoded physical addresses,
  which does not apply to the SG-only MCDMA); kept only as a register-model reference.

## Measurements to collect

Record these in the README once hardware runs; they feed directly back into the parent
design.

| Measurement | Why |
|---|---|
| LUT/FF/BRAM at 2+2 and 4+4 | Extrapolate to 8+8; decides MCDMA vs. 8x `axi_dma` |
| Sustained aggregate MB/s, all channels | Confirm the bandwidth margin is real |
| Max observed gap between FIFO services | The actual underrun margin |
| Interrupt latency, idle vs. loaded system | Matters only for mode 2, but cheap to take |
| Descriptor fetch overhead vs. chunk size | Guides chunk sizing at scale |

## Gotchas worth knowing before you start

- **TrustZone.** PS peripherals default to secure mode, and accesses with
  `AxPROT[1]=1` return `DECERR`. If transfers fail immediately with no other
  explanation, check this before debugging anything else.
- **Command reordering.** The HP interface may reorder both reads and writes, and
  read data interleaving can occur. MCDMA handles this; custom PL masters must.
- **Don't use 32-bit HP mode.** Upsizing requires `AxCACHE[1]` to be set, and wait
  states appear if the write command isn't asserted a cycle ahead of the first data
  beat. The bandwidth savings are irrelevant here and the failure modes are subtle.

## Trying it on hardware

After a `make PROJECT=ex07_dma`, write the SD image, boot the board, and log in. The
steps below verify the pieces bottom-up: first that the buffer and the register
window came up, then the actual DMA round trip. Everything Xilinx-specific in the
block design and the program is still flagged `VALIDATE` -- these checks are how you
confirm those guesses.

### 1. Confirm the `u-dma-buf` region allocated

```sh
dmesg | grep u-dma-buf                 # expect a udmabuf0 line with a phys address
ls -l /dev/udmabuf0                     # node exists (root-owned by default)
cat /sys/class/u-dma-buf/udmabuf0/phys_addr
cat /sys/class/u-dma-buf/udmabuf0/size  # >= REGION_BYTES (~12 KB); the DT reserves 4 MiB
```

If `/dev/udmabuf0` is missing, the `reserved-memory` / `u-dma-buf` device-tree node
did not take -- check `dmesg` for allocation failures (CMA/reserved-memory failures
are quiet) and confirm the base address in `device_tree.dtsi` doesn't overlap
anything on this board.

> **`of_reserved_mem_device_init failed. return=-22`** means the reserved region is
> not aligned to the CMA minimum alignment (4 MiB on 32-bit ARM). The region's base
> *and* size must both be 4 MiB-aligned -- `device_tree.dtsi` uses a 4 MiB region at
> `0x30000000` for this reason. Shrinking it below 4 MiB reintroduces the error.

### 2. Confirm the MCDMA control window bound to `pl-reg` (non-root path)

```sh
dmesg | grep pl-reg                     # expect "/dev/mcdma ready (mode 0666): 0x40400000 ..."
ls -l /dev/mcdma                        # crw-rw-rw-  (non-root)
```

The project's `device_tree.dtsi` overrides this node's `compatible` to a private
`zynq-toolbox,mcdma-userspace` string, so no in-kernel driver matches it and `pl-reg`
claims it deterministically (this avoids relying on the `xilinx_dma` probe failing --
see the dtsi comment for why PetaLinux tags a standalone MCDMA as `xlnx,eth-dma`).
Confirm the override took:

```sh
tr '\0' '\n' < /sys/firmware/devicetree/base/pl-bus/axi_mcdma@40400000/compatible
# expect a single line: zynq-toolbox,mcdma-userspace
```

- If `/dev/mcdma` exists, the non-root path works.
- If the compatible still shows the `xlnx,...` strings, the dtsi override didn't
  apply -- confirm the `&mcdma` label resolves (it comes from the Vivado instance
  name `mcdma`) and that `device_tree.dtsi` rebuilt into `system-user.dtsi`.
- The program also runs via its `/dev/mem` fallback under `sudo` regardless.

### 3. Run the loopback

The MCDMA register window is non-root (via `pl-reg`), but the `u-dma-buf` buffer node
(`/dev/udmabuf0`) comes up `root`-owned, and this rootfs deliberately avoids udev, so
there is no rule to relax it. Run under `sudo` for now (a boot-time `chmod` of
`/dev/udmabuf*` would remove even this -- see TODO):

```sh
sudo mcdma-loopback
```

Expected output -- each channel returns its data and the completed byte count:

```
mcdma-loopback: 2-channel prebuffered MCDMA loopback via u-dma-buf
MCDMA control: /dev/mcdma (pl-reg, no root)
u-dma-buf udmabuf0: phys 0x30000000, 12288 bytes used of 4194304

  ch0  ok    received 2048/2048 bytes
  ch1  ok    received 2048/2048 bytes

All channels round-tripped.
```

If it fails (on another board, or after a change), the `dump_status` output printed on
timeout shows the engine state. Common cases:

- **Both channels time out, 0 bytes.** The engine never started or errored. Check the
  dumped `MM2S SR` / `S2MM SR` (bit 0 = HALTED) and `CH_ERR` registers, and the
  TrustZone `DECERR` gotcha (PS peripherals default secure; `AxPROT[1]=1` returns
  `DECERR`). Two subtle bugs already fixed and worth knowing: the MCDMA descriptor
  `control` word is at offset `0x14` (not the AXI-DMA `0x18`), and Run/Stop must be set
  in *both* the per-channel and the common control register.
- **Data mismatch but correct byte count.** Data flowed but TDEST routing is wrong
  (channel *i*'s data landed in another S2MM channel). Check the MCDMA channel-group
  registers and that MM2S drives TDEST from the channel index.
- **`mmap`/`open` errors.** See sections 1-2 (and remember `sudo` for the buffer node).

### 4. (Optional) prove the cache-coherency handling is real

The single `sync_for_device` before the run is load-bearing. To see the failure it
prevents, comment out the `sync_for_device` call in `mcdma-loopback.c`, rebuild, and
re-run: you should get intermittent data mismatches as the DAC data sits in CPU cache
instead of DDR. Restore the sync afterward. Knowing what that corruption looks like
directly informs the parent project.

## Build integration

A normal `make PROJECT=ex07_dma` produces an SD image where:

- the block design (bitstream + `.xsa`) contains the MCDMA and, per the `datapath`
  selector, either the single TDEST-routed loopback FIFO (default) or the per-channel
  FIFOs,
- `u-dma-buf` is built out-of-tree via `kernel_modules/` (the build script generates
  its recipe -- no hand-written `meta-user` recipe -- and appends
  `KERNEL_MODULE_AUTOLOAD`, so it loads at boot like every module this repo ships),
- the demonstration program is cross-compiled into the rootfs.

## Open questions / TODO

- [x] Rework `block_design.tcl` from the single-channel `axi_dma` scaffold to a
      parameterized `axi_mcdma` (first pass: `num_ch`-per-direction MCDMA, GP0
      control, HP0 memory path incl. SG, per-channel interrupts, and a `datapath`
      selector for either a single TDEST-routed loopback or the fuller per-channel
      structure). Xilinx-side `CONFIG.*`/pin names are flagged in-file for validation.
- [ ] Validate and bring up the `datapath = per_channel` branch (TDEST demux/mux via
      `axis_switch`), then add the programmable-rate PL traffic generator/checker
      between the per-channel DAC and ADC FIFOs (needs a new custom core).
- [ ] Verify the MCDMA buffer-length register width and widen to 23 bits.
- [ ] Decide `TLAST` policy on the S2MM side and implement it in the generator.
- [x] Wire `u-dma-buf` allocation (payload + descriptor-ring region) and the
      single-sync coherency path into software. First pass: one `reserved-memory`
      region in `cfg/.../petalinux/<ver>/device_tree.dtsi` -> `/dev/udmabuf0`,
      carved by `software/mcdma-loopback/mcdma-loopback.c`.
- [ ] Run without `sudo`: `/dev/udmabuf0` comes up `root`-owned and this rootfs
      avoids udev, so the buffer node needs a boot-time `chmod` (the register window
      is already non-root via `pl-reg`). Until then the demo runs under `sudo`.
- [x] Bind the MCDMA control window to a `pl-reg` node for non-root register access.
      `device_tree.dtsi` overrides the node's compatible to a private
      `zynq-toolbox,mcdma-userspace` string so no in-kernel driver matches it, and
      `pl-reg` (symlinked into `kernel_modules/`) claims it deterministically as
      `/dev/mcdma`. The program falls back to `/dev/mem` if unbound.
- [x] Build the mode-1 (prebuffered) round-trip demo -- validated on hardware (2+2,
      both channels byte-exact). MCDMA register/descriptor programming is confirmed
      against mainline `xilinx_dma.c` (`software/mcdma-loopback/mcdma-loopback.c`).
- [ ] Add independent-rate and mid-run-pause tests.
- [ ] Add deliberate underrun and missed-flush fault injection.
- [ ] Collect the measurements table.
- [ ] Try the dmaengine path (option A) and compare against direct register control.
- [x] Fill in concrete "Trying it on hardware" steps (see the section above).
- [ ] _(stretch)_ Mode 2 streaming with descriptor append.

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
