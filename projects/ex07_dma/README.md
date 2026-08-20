***Updated 2026-08-20***

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
- Packet-atomic `axis_switch` arbitration (`ARB_ON_TLAST`) to merge streams `num_ch -> 1`

> Status (working): the datapath round-trips all four channels
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

`block_design.tcl` stands up the MCDMA and a per-channel AXI4-Stream datapath, all
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

The AXI4-Stream datapath between MM2S and S2MM gives each channel its own FIFOs:

```
M_AXIS_MM2S -> mm2s_demux -> dac_fifo[i] -> (rate-gen core, TODO) -> adc_fifo[i] -> s2mm_mux -> S_AXIS_S2MM
               (axis_switch,                                                        (axis_switch,
                1 -> num_ch by TDEST)                                                num_ch -> 1)
```

Each channel gets its own DAC and ADC FIFO, mirroring rev_d_shim (where a SPI core
sits between them). Today the DAC->ADC gap is a plain wire; the programmable-rate
traffic-gen core drops in there later. `TDEST == i` is preserved end to end, so MCDMA
S2MM routes each channel's data back to itself.

The `num_ch -> 1` recombine is a stock `axis_switch` (`ROUTING_MODE 0`) set to arbitrate
packet-atomically: it grants one input and holds it through `TLAST` before advancing
round-robin, so packets are never interleaved onto the single S2MM stream and no channel
starves. This works only with `HAS_TLAST` set explicitly so `ARB_ON_TLAST` takes hold
(see [Design notes](#design-notes)).

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
+ `.xsa`) contains the MCDMA and the AXI4-Stream datapath, `u-dma-buf` is built
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

The DMA foundation is proven on hardware. What remains turns it into a prototype that
drops cleanly onto rev_d_shim. The items below are **ordered** -- each builds on the one
before, and the first four are the load-bearing path. Everything under "Deferred" is
explicitly *not* needed for the prototype and is recorded only so the design does not
foreclose it.

**Prototype path (do in order):**

1. [ ] **Programmable-rate traffic generator/checker core.** Drop it into the marked
       `dac_fifo_i -> adc_fifo_i` insertion point in `block_design.tcl` (currently a
       plain wire). Per channel it (a) drains its DAC FIFO at a register-programmed
       rate with a programmable pause, and (b) fills its ADC FIFO with a checkable
       pattern at its own rate. This stands in for rev_d_shim's SPI core and is the
       prerequisite for every test below. Follow the repo core layout
       (`cores/base/<core>` + a cocotb testbench).
2. [ ] **Independent-rate and mid-run-pause tests.** With the core in place, run each
       channel at a different rate and pause channels mid-run; confirm per-channel
       independence end to end (the parent project's hard constraints 3 and 4).
3. [ ] **Fault injection + software detection.** Deliberately underrun a DAC FIFO
       (consume before the DMA fills) and overflow an ADC FIFO (stall S2MM), plus a
       missed-`sync_for_device` corruption case. Characterize exactly what software can
       observe -- this de-risks rev_d_shim's must-not-happen constraint (1) and is the
       last genuinely load-bearing unknown.
4. [ ] **Completion/error interrupt via UIO.** Aggregate the per-channel IRQs onto a
       `generic-uio` node, block on `read()`/`poll()` of `/dev/uioN` for completion and
       error, and keep the happy path polled. Yields the completion-latency number and
       makes step 3's faults visible. Note for the port: rev_d_shim folds DMA errors
       into `hw_manager`'s single error-alert IRQ, so this standalone UIO is an ex07
       measurement vehicle, not a pattern to copy verbatim.

Reaching step 4 makes ex07 a sufficient prototype: it demonstrates independent-rate
prebuffered DMA, per-channel pause, and detectable fault handling on the exact 8+8
topology rev_d_shim needs.

**Deferred (not required for the prototype):**

- [ ] Throughput/latency table: sustained aggregate MB/s, max FIFO-service gap, and
      descriptor overhead vs. chunk size. Low value here -- bandwidth has ~20x margin
      (`PROJECT_BRIEF` section 6), so these confirm rather than decide anything.
- [ ] dmaengine path (option A: `CONFIG_XILINX_DMA` + `dmaengine_prep_slave_sg`) vs.
      direct register control. The decision is already made (direct register, proven),
      so this is a "for completeness" comparison; note dmaengine pairs awkwardly with
      `u-dma-buf` (wants `dma_alloc_coherent`).
- [ ] (stretch) Mode 2 streaming: append descriptors ahead of the ring tail during a
      run. Works with MCDMA as-is (no cyclic mode); attempt only after the path above.

Done so far: the MCDMA block design (`num_ch`-per-direction, GP0 control, HP0 memory +
SG, per-channel interrupts) and the per-channel demux/FIFO/mux datapath; `u-dma-buf`
allocation + single-sync coherency; non-root access via `pl-reg` + the boot-time chmod;
the prebuffered round-trip demo, validated on hardware at 4+4; and the utilization
measurement (synth, xc7z020-3, Vivado 2024.2) that settled MCDMA vs. 8x `axi_dma`.
Whole ex07 at 8+8 (16 streams, the rev_d_shim size) is **15,089 LUT / 15,691 FF /
19 BRAM36 + 4 BRAM18 / 0 DSP**, of which **~13.9k LUT** is net-new engine (mcdma 8.7k,
HP0 SmartConnect 4.4k, GP0 control 0.5k, demux+mux 0.4k) plus 3 BRAM36 + 4 BRAM18.
Extrapolated onto rev_d_shim (22.3k LUT / 86 BRAM36 at 4 boards today), 8 boards +
MCDMA lands at **~52-54k LUT (~97-102%)** -- LUT, not BRAM, becomes the binding
constraint, while the FIFOs shrinking to elastic buffers frees most of the BRAM. See
`PROJECT_BRIEF` sections 4 and 7.

Done so far: the MCDMA block design (`num_ch`-per-direction, GP0 control, HP0 memory +
SG, per-channel interrupts) and the per-channel demux/FIFO/mux datapath; `u-dma-buf`
allocation + single-sync coherency; non-root access via `pl-reg` + the boot-time chmod;
and the prebuffered round-trip demo, validated on hardware at 4+4.

## Design notes

Two `s2mm_mux` bugs surfaced while bringing up `per_channel`; both cost real debugging
time and are easy to hit again:

- `axis_switch` TDEST windows take hex. The demux's per-MI `BASETDEST`/`HIGHTDEST`
  are `bitString` params: pass `[format 0x%08X $i]`, not a bare integer, or the derived
  `C_M_AXIS_*TDEST_ARRAY` modelparam rejects any value needing more than one bit (0 and
  1 slip through, which hid it until `num_ch >= 3`). A single MI also defaults to the
  TDEST window `[0,0]` and silently drops every higher channel, so a mux MI's window
  must span `[0, num_ch-1]`.
- S2MM recombine needs packet-atomic arbitration. By default a stock `axis_switch`
  (`ROUTING_MODE 0`) re-arbitrates per beat, interleaving channels onto the single S2MM
  stream; MCDMA latches `TDEST` at start-of-packet and needs each packet contiguous, so
  the mix lands on one channel and the rest starve. The switch will instead arbitrate on
  packet boundaries (`ARB_ON_TLAST`), but only if `HAS_TLAST` is set explicitly -- left
  to propagation the tool silently drops `ARB_ON_TLAST` back to 0 (it depends on `TLAST`
  being present). With both set, the arbiter holds a granted input through `TLAST` and
  all four channels round-trip byte-exact.

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
