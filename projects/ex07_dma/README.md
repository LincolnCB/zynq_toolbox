***Updated 2026-08-24***

# Example 07: DDR-Backed FIFO Buffers via MCDMA

Example 07 builds a complete DMA data path between the PS (DDR) and the PL and uses it
to give a set of shallow PL FIFOs a large backing store in DDR. The PS preloads long
buffers into DDR ahead of time, an AXI MCDMA engine feeds them into on-chip FIFOs on
demand, and drains PL-produced data back to DDR far faster than the PS could move it
register-by-register. `num_ch` MM2S and `num_ch` S2MM channels run independently
(default 8), each bound to its own FIFO and addressed by `TDEST`.

The project introduces the following tools and concepts:
- Driving an AXI MCDMA with independent per-channel scatter-gather rings
- Using DDR as a large FIFO backing store (the "prebuffered" playback/capture model)
- Physically contiguous DMA buffers with `u-dma-buf` plus explicit cache sync
- Non-root MCDMA register access via a `pl-reg` node
- `TDEST` routing and `TLAST` packet semantics across a demux -> FIFO -> mux datapath
- Packet-atomic `axis_switch` arbitration (`ARB_ON_TLAST`) to merge streams `num_ch -> 1`
- A programmable-rate PL pacer between the FIFOs, controlled non-root through a
  shared `cfg`/`sts` register pair (the ex05 `pl-reg` misc-device approach)

> The datapath round-trips every channel byte-for-byte on hardware without root:
> `mcdma-loopback` passes for all channels and any subset, the per-channel
> `axi_rate_gen` pacer throttles and pauses each channel independently under `rate-ctl`,
> and `fault-inject` confirms the cache sync is load-bearing (skipping it silently
> corrupts every channel). A coordinated `halt -> clear -> reinit -> re-run` brings a
> channel back byte-exact after a mid-run FIFO clear (`halt-reset`), with `noclear`
> confirming the register-driven FIFO clear is load-bearing. The remaining work (see
> [What's left](#whats-left)) builds on this foundation: the UIO completion/error
> interrupt path and the throughput/latency table.

## Why this example exists

Each item below is an open question in the parent project that this example closes out:

1. Is the Linux MCDMA path usable? Resolved: userspace register control works.
   `mcdma-loopback` drives the MCDMA over a `pl-reg`-mapped window and round-trips data,
   so the parent project can proceed without depending on the lightly-used dmaengine
   MCDMA driver (`drivers/dma/xilinx/xilinx_dma.c`, `device_prep_slave_sg` only).
2. What does MCDMA cost in LUTs? Resolved: synthesized at 8+8 (`xc7z020-3`) the
   net-new engine is ~13.9k LUT, which makes MCDMA cheaper than eight separate
   `axi_dma` and lands the 8-board rev_d_shim at ~52-54k LUT -- so LUT, not BRAM, is
   the binding constraint. See [Utilization](#utilization).
3. What is the worst-case service latency? Open: the `axi_rate_gen` pacer supplies the
   controllable load, but the number itself needs the UIO completion path (below).
4. Does the coherency handling work? Resolved: a single `sync_for_device` before
   each run is load-bearing; skipping it reproduces silent corruption (see
   `fault-inject nosync` under [Trying it on hardware](#trying-it-on-hardware)).
5. What does underrun/overflow look like from software? It doesn't -- and it must not.
   In rev_d_shim, DAC/ADC buffer under/overflow is detected in the PL by the DAC/ADC
   cores and folded into `hw_manager`'s status word and `ps_interrupt`; the PS/DMA side
   never watches for it and never times out. A channel waiting arbitrarily long for a
   trigger is normal, not a fault, and a duplicate PS-side check would conflict with the
   cores. The DMA's only response to a fault or shutdown is halt/reset (the coordinated
   `halt-reset`, [section 8](#8-coordinated-halt--clear--reset)). The one data hazard the
   PS genuinely owns is cache coherency, which `fault-inject nosync` reproduces.

Goal-wise, the point is independent channels -- several DMA regions in flight at once,
each bound to its own FIFO, independently startable and running at unrelated rates --
not raw throughput. The channel count is one Tcl parameter (`num_ch`), so scaling for
the LUT-cost measurement is a one-line change.

## Block design

`block_design.tcl` stands up the MCDMA and a per-channel AXI4-Stream datapath, all
clocked at 100 MHz off `FCLK_CLK0`. The channel count is the Tcl parameter `num_ch`
(default 8).

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
- A shared `axi_cfg_register` (`rate_cfg`) and `axi_sts_register` (`rate_sts`) on
  GP0 -- 32 control/status bits per channel -- backing the per-channel pacers
  (the ex02/ex05 `CFG -> logic -> STS` idiom). `pl-reg` publishes them non-root as
  `/dev/rate_cfg` and `/dev/rate_sts` with no driver change (its match table
  already lists the cfg/sts compatibles).
- A shared `axi_cfg_register` (`buf_reset`) on GP0 -- one bit per channel --
  driving a per-channel datapath FIFO reset. Bit `i`, ANDed with the global
  peripheral reset and fed through a per-channel `proc_sys_reset`, clears channel
  `i`'s DAC and ADC FIFO (the rev_d_shim `axi_sys_ctrl data_buf_reset` pattern:
  slice -> `NOT` -> `proc_sys_reset`). `pl-reg` publishes it non-root as
  `/dev/buf_reset`. This backs the coordinated halt/clear/reset path.

The AXI4-Stream datapath between MM2S and S2MM gives each channel its own FIFOs:

```
M_AXIS_MM2S -> mm2s_demux -> dac_fifo[i] -> rate_gen[i] -> adc_fifo[i] -> s2mm_mux -> S_AXIS_S2MM
               (axis_switch,                (rate pacer)                 (axis_switch,
                1 -> num_ch by TDEST)                                     num_ch -> 1)
```

Each channel gets its own DAC and ADC FIFO, mirroring rev_d_shim (where a SPI core
sits between them). In that gap sits `axi_rate_gen`, a small custom core that
forwards the stream unchanged (`TDEST`/`TLAST` preserved) but throttles it to a
per-channel programmed rate and can pause it -- standing in for the SPI core's
pacing. `TDEST == i` is preserved end to end, so MCDMA S2MM routes each channel's
data back to itself. Its per-channel control (`RATE_DIV`, `PAUSE`) and status
(`BEAT_COUNT`) are slices of `rate_cfg`/`rate_sts`.

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

`software/rate-ctl/rate-ctl.c` drives the per-channel `axi_rate_gen` pacers. It opens
`/dev/rate_cfg` and `/dev/rate_sts`, `mmap`s each once, and then reads/writes a 32-bit
word per channel (`RATE_DIV` + `PAUSE` in cfg, `BEAT_COUNT` in sts) -- the same
non-root register pattern as ex05's `reg-driver`, no root and no hardcoded addresses.
Program per-channel rates with it, run `mcdma-loopback` to push traffic, then read the
beat counts back to see each channel advanced. `mcdma-loopback` also reports its per-run
`elapsed` time, which scales with a throttled channel's rate, so a single-channel run is
the clearest way to see a rate take effect.

`software/fault-inject/fault-inject.c` exercises the one data hazard the PS/DMA side
owns: cache coherency. It runs the same prebuffered transfer as `mcdma-loopback`. With no
argument it does a full-sync baseline and expects every channel `ok`. With `nosync` it
flushes the SG descriptors and an all-zero payload to DDR, then writes the real
per-channel pattern into the cached `src` but *skips the payload `sync_for_device`*: the
MCDMA reads the stale zeros over the non-coherent HP0 port, so every channel *completes*
with full length and no `CH_ERR` but `dst` comes back all-zero -- silent corruption a
content check catches. The descriptors are flushed deliberately so the engine runs
cleanly and the fault is pure data corruption; skipping the descriptor flush as well just
yields nondeterministic engine errors. It classifies each channel `ok` / `corrupt` /
`error` and checks the result against what was injected (`PASS`/`FAIL`).

Deliberately, `fault-inject` does *not* check for buffer under/overflow or treat a
stalled channel as a fault: in rev_d_shim those are detected in the PL by the DAC/ADC
cores and raised through `hw_manager`, and the PS must tolerate an indefinitely stalled
channel (a sequence waiting for a trigger) without timing out. Recovering from a stall or
shutdown is halt/reset, covered by [What's left](#whats-left). To keep the
coherency test deterministic regardless of any prior `rate-ctl` state, the tool clears all
pacers to full rate before running and resets both MCDMA directions on exit.

`software/halt-reset/halt-reset.c` exercises the coordinated halt/clear/reset path --
the DMA's only response to a fault or shutdown. A FIFO-only reset is unsafe to pulse
while an MCDMA channel is mid-transfer (the MM2S side loses byte-count sync and the
S2MM side loses `TLAST` framing while the MCDMA's descriptor/run state is untouched),
so the reset is an ordered sequence: halt the MCDMA (soft-reset both directions), clear
the datapath FIFOs (`buf_reset`), reinitialize the descriptor rings, then re-run. To
have something real to clear, it first *strands* a short complete packet
(`STRAND_WORDS`, with `TLAST`) in each DAC FIFO with that channel's pacer paused, so the
packet lodges in the FIFO and never reaches S2MM. With no argument it runs the full
sequence and expects every channel `ok` -- byte-exact after the clear. With `noclear` it
skips the `buf_reset` pulse: the stranded packet stays in the FIFO, so the re-run drains
that stale data first and every channel comes back short and mismatched (`corrupt`),
proving the FIFO clear is load-bearing. It classifies each channel and checks the result
against what was injected (`PASS`/`FAIL`), then leaves the system clean on exit.

Non-root access: the register window is non-root via `pl-reg`. `u-dma-buf` exposes
two root-owned interfaces the program touches -- the `/dev/udmabuf0` mmap node (0600)
and the sysfs cache-sync controls `/sys/class/u-dma-buf/udmabuf0/sync_*` (0664) -- with
no mode knob; miss the sysfs controls and `mmap` still succeeds but the first
`sync_for_device` fails `EACCES`. The project's top-level `boot_script.sh` `chmod`s both
to 0666 at boot (installed as an `/etc/init.d` service by
`scripts/petalinux/boot_script.sh`; this rootfs has no udev), so the whole demo runs as
an ordinary user.

Cache coherency: the HP ports are not coherent with L1/L2, but prebuffered mode needs
only one `sync_for_device` before the run and one `sync_for_cpu` after (no per-chunk
sync), on a cached mapping so filling multi-MB patterns stays fast.

`software/xilinx-dma-test/` is superseded (it drove a plain `axi_dma` in direct-register
mode) and kept only as a register-model reference.

## Device tree

`cfg/.../petalinux/<ver>/device_tree.dtsi` declares two things:

- a `reserved-memory` region (4 MiB at `0x30000000`) that `u-dma-buf` claims as
  `/dev/udmabuf0`. The base and size must both be 4 MiB-aligned or
  `of_reserved_mem_device_init` fails `-22` on 32-bit ARM.
- a `compatible` override on the MCDMA node to a private
  `zynq-toolbox,mcdma-userspace` string, so no in-kernel driver matches it and `pl-reg`
  claims it deterministically as `/dev/mcdma` (rather than relying on the `xilinx_dma`
  probe failing -- PetaLinux otherwise tags a standalone MCDMA as `xlnx,eth-dma`).

The `rate_cfg`/`rate_sts`/`buf_reset` windows need no device-tree entry: PetaLinux
auto-generates their nodes from the block design and `pl-reg` binds them by their
cfg/sts compatibles, naming `/dev/rate_cfg`, `/dev/rate_sts` and `/dev/buf_reset` from
the Vivado instance labels -- exactly the ex05 mechanism.

## Build integration

A normal `make PROJECT=ex07_dma` produces an SD image where the block design (bitstream
+ `.xsa`) contains the MCDMA, the AXI4-Stream datapath, the per-channel rate
pacers, and the per-channel FIFO reset, `u-dma-buf` is built out-of-tree from
`kernel_modules/` and autoloaded, the `boot_script.sh` chmod service is installed (by
`scripts/petalinux/boot_script.sh`, guarded by `scripts/check/boot_script.sh`), and
`mcdma-loopback`, `rate-ctl`, `fault-inject`, and `halt-reset` are cross-compiled into
the rootfs.

## Trying it on hardware

After `make PROJECT=ex07_dma`, write the SD image, boot, and log in. Run the commands
below in order; each lists what to expect.

### 1. Confirm the driver nodes came up non-root

```sh
dmesg | grep pl-reg
```

Expect one line per window, each `mode 0666`:

```
pl-reg 40400000.axi_mcdma: /dev/mcdma ready (mode 0666): 0x40400000 size 0x10000, compatible "zynq-toolbox,mcdma-userspace"
pl-reg 40410000.axi_cfg_register: /dev/rate_cfg ready (mode 0666): 0x40410000 size 0x10000, compatible "xlnx,axi-cfg-register-1.0"
pl-reg 40420000.axi_sts_register: /dev/rate_sts ready (mode 0666): 0x40420000 size 0x10000, compatible "xlnx,axi-sts-register-1.0"
pl-reg 40430000.axi_cfg_register: /dev/buf_reset ready (mode 0666): 0x40430000 size 0x10000, compatible "xlnx,axi-cfg-register-1.0"
```

```sh
ls -l /dev/mcdma /dev/rate_cfg /dev/rate_sts /dev/buf_reset /dev/udmabuf0
```

Expect all four present and world-accessible (`crw-rw-rw-`). If `/dev/udmabuf0` is
missing the `reserved-memory` node didn't take (CMA failures are quiet -- check
`dmesg`); if `/dev/mcdma` is missing the `compatible` override didn't apply and the
MCDMA bound to a kernel driver (the program then still runs via its `/dev/mem` fallback
under `sudo`).

### 2. Round-trip every channel

```sh
mcdma-loopback
```

Expect every channel `ok` (no args runs all; pass indices to run a subset):

```
mcdma-loopback: 8-channel prebuffered MCDMA loopback via u-dma-buf
running channels: 0 1 2 3 4 5 6 7

MCDMA control: /dev/mcdma (pl-reg, no root)
u-dma-buf udmabuf0: phys 0x30000000, 36864 bytes used of 4194304

  ch0  ok    received 2048/2048 bytes
  ch1  ok    received 2048/2048 bytes
  ch2  ok    received 2048/2048 bytes
  ch3  ok    received 2048/2048 bytes
  ch4  ok    received 2048/2048 bytes
  ch5  ok    received 2048/2048 bytes
  ch6  ok    received 2048/2048 bytes
  ch7  ok    received 2048/2048 bytes

elapsed 0.1 ms
All channels round-tripped.
```

### 3. Read the pacer beat counters

```sh
rate-ctl
```

Expect every channel at `rate_div=0 pause=0`, and `beat_count = 512` after the run above
(2048 bytes / 4 bytes per beat):

```
rate-ctl: 8 channels via /dev/rate_cfg + /dev/rate_sts (no root)

  ch   rate_div  pause   beat_count
   0          0    0            512
   1          0    0            512
   2          0    0            512
   3          0    0            512
   4          0    0            512
   5          0    0            512
   6          0    0            512
   7          0    0            512
```

### 4. Throttle a channel

```sh
rate-ctl set 2 15
```

Expect `ch2: rate_div=15 pause=0` -- channel 2 now passes one beat every 16 cycles.

```sh
mcdma-loopback
```

Expect all channels still `ok`: the pacer only throttles, it never corrupts. Channel 2
simply takes longer.

```sh
rate-ctl all 0
```

Expect `all channels: rate_div=0 pause=0`, resetting every channel to full rate.

### 5. Pause a channel mid-run

```sh
rate-ctl pause 3
```

Expect `ch3: paused`.

```sh
mcdma-loopback
```

Expect channel 3 alone to stall: its S2MM never completes, so the program times out and
reports `ch3 FAIL received 0/2048 bytes` with an all-zero `dst` (starvation), while the
other seven round-trip `ok`. This is the intended demonstration -- a paused channel
backpressures only itself. On timeout the `dump_status` block prints per-channel
`MM2S`/`S2MM` `SR` (bit 0 = HALTED), `CH_ERR`, each descriptor's status, and
`src[0..3]` vs `dst[0..3]`: an all-zero `dst` is starvation, another channel's high byte
would be a misroute.

```sh
rate-ctl
```

Expect `ch3` at `pause=1` with its `beat_count` frozen while the others advanced.

```sh
rate-ctl run 3
```

Expect `ch3: running`; a subsequent `mcdma-loopback` passes on all channels again.

### 6. Run channels at independent rates

Throttle a few channels to different rates and confirm each still round-trips -- the
parent project's independent-channel requirement (hard constraints 3 and 4). The channels
share one physical S2MM port, so they serialize through the mux packet-by-packet rather
than truly streaming at once; the clearest per-channel signal is the `elapsed` time of a
single-channel run, which scales with that channel's rate.

Start from full rate and note the baseline timing:

```sh
rate-ctl all 0
mcdma-loopback 0
```

Expect `ch0 ok` with `elapsed 0.1 ms` -- a single full-rate channel moves its 512 beats in
well under a millisecond.

Give three channels distinct rates:

```sh
rate-ctl set 1 999
rate-ctl set 2 7999
rate-ctl set 3 15999
```

Run each of those channels on its own and watch the `elapsed` time track the rate:

```sh
mcdma-loopback 1
mcdma-loopback 2
mcdma-loopback 3
```

Each round-trips `ok`, and `elapsed` scales linearly with `rate_div`. Measured on hardware
(about `2 x (rate_div + 1)` clock cycles per beat at 100 MHz over the 512-beat payload):

| channel | rate_div | measured elapsed |
|---|---|---|
| 0 | 0 | 0.1 ms (full rate) |
| 1 | 999 | 10.3 ms |
| 2 | 7999 | 81.8 ms |
| 3 | 15999 | 163.5 ms |

Run every channel at once, read the beat counts, then restore full rate:

```sh
mcdma-loopback
rate-ctl
rate-ctl all 0
```

Expect all eight `ok`; the aggregate `elapsed` is set by the slowest channel (~164 ms
here) because the channels overlap. `rate-ctl` shows every channel's `beat_count` has
advanced -- it accumulates since boot, +512 per run -- confirming the pacers ran.

This test throttles the *rate*, not the packet size: keep each channel's single packet at
the 512-beat default, because the `s2mm_mux` re-arbitration backstop
(`ARB_ON_MAX_XFERS 1024`) re-arbitrates a single packet larger than ~1024 beats mid-packet
and corrupts its framing.

### 7. Prove the cache sync is load-bearing

```sh
fault-inject
fault-inject nosync
```

The baseline (`fault-inject` with no argument) does a full-sync run and prints every
channel `ok` and `PASS`. `fault-inject nosync` stages the real pattern into the cached
buffer but skips the payload `sync_for_device`, so the MCDMA transfers the stale zeros
still in DDR: every channel is `corrupt` -- completed with full length
(`desc.status` `0x8c000800`) and `CH_ERR` still `0`, but `dst` all-zero:

```
fault-inject: 8-channel MCDMA cache-coherency check
mode: nosync -- skip payload sync_for_device (expect every channel corrupt)

MCDMA control: /dev/mcdma (pl-reg, no root)
u-dma-buf udmabuf0: phys 0x30000000, 36864 bytes used of 4194304

(skipping the payload sync_for_device -- the DMA will read stale DDR)

all descriptors completed in 0.1 ms

  ch  outcome     len(bytes)  desc.status  err  detail
   0  corrupt          2048   0x8c000800   0   completed but dst != src
   ...
   7  corrupt          2048   0x8c000800   0   completed but dst != src

  MM2S SR=0x00000002 CH_ERR=0x00000000   S2MM SR=0x00000002 CH_ERR=0x00000000

PASS: every channel produced its expected outcome (corrupt)
```

That silent corruption, catchable only by a content check, is exactly why the sync is
load-bearing. It replaces the older manual method of commenting out the
`sync_for_device` call in `mcdma-loopback.c` -- no rebuild. The run ends `PASS` when the
outcomes match (all `ok` for baseline, all `corrupt` for `nosync`), and resets the MCDMA
on exit.

If any transfer fails immediately with no data, suspect the TrustZone `DECERR` gotcha
(see [Design notes](#design-notes)). If you get `Permission denied`, the boot script
didn't run -- check `/etc/init.d/boot-script` and fall back to `sudo mcdma-loopback`.

### 8. Coordinated halt / clear / reset

```sh
halt-reset
```

The tool strands a short packet in each DAC FIFO (pacer paused), then halts the MCDMA,
pulses `buf_reset` to flush the FIFOs, reinitializes the descriptor rings, and re-runs a
full-length transfer. Expect every channel `ok` -- byte-exact after the mid-run clear:

```
halt-reset: 8-channel coordinated halt / FIFO clear / reinit / re-run
mode: clear -- full sequence (expect every channel ok)

MCDMA control: /dev/mcdma (pl-reg, no root)
u-dma-buf udmabuf0: phys 0x30000000, 36864 bytes used of 4194304

stranding a 64-word packet in each DAC FIFO (pacers paused)...
  MM2S SR=0x00000002 CH_ERR=0x00000000  (data now held in the DAC FIFOs)

halt: soft-resetting both MCDMA directions
clear: pulsing buf_reset = 0xff to flush the datapath FIFOs
reinit: rebuilding the descriptor rings with a fresh payload
re-run: transferring the fresh payload

all descriptors completed in 0.1 ms

  ch  outcome     len(bytes)  desc.status  err  detail
   0  ok               2048   0x8c000800   0
   ...
   7  ok               2048   0x8c000800   0

PASS: every channel produced its expected outcome (ok)
```

Then prove the FIFO clear is load-bearing by skipping it:

```sh
halt-reset noclear
```

With the `buf_reset` pulse skipped, each channel's stranded 64-word packet stays in the
FIFO, so the re-run drains that stale data first and S2MM completes early on its
`TLAST` -- every channel comes back short (256 bytes) and mismatched, classified
`corrupt`. That is exactly why the halt must be paired with a FIFO clear before a
restart. The tool restores a clean state (pacers unpaused, FIFOs cleared, MCDMA reset)
on exit, so a following `mcdma-loopback` round-trips all channels again.

## What's left

The DMA foundation is proven on hardware (summarized above). What remains turns it into a
prototype that drops cleanly onto rev_d_shim:

1. [ ] **Completion/error interrupt via UIO.** Aggregate the per-channel IRQs onto a
       `generic-uio` node, block on `read()`/`poll()` of `/dev/uioN` for completion and
       error, and keep the happy path polled. Yields the completion-latency number and
       surfaces MCDMA-level completion/error events (bus/decode errors, not the silent
       coherency case). rev_d_shim folds DMA errors into `hw_manager`'s single error-alert
       IRQ, so this standalone UIO is an ex07 measurement vehicle, not a pattern to copy
       verbatim.

With this done, ex07 demonstrates independent-rate prebuffered DMA, coherency-safe
transfers, coordinated halt/clear/reset, and completion/error interrupts on the exact 8+8
topology rev_d_shim needs. Deferred and not required for the prototype: a
throughput/latency table (sustained MB/s, max FIFO-service gap, descriptor overhead vs.
chunk size) -- bandwidth has ~20x margin (`PROJECT_BRIEF` section 6), so it would confirm
rather than decide anything.

## Utilization

Synthesized at 8+8 (16 streams, the rev_d_shim size) for `xc7z020-3` (Vivado 2024.2), the
whole example is **15,089 LUT / 15,691 FF / 19 BRAM36 + 4 BRAM18 / 0 DSP**, of which
**~13.9k LUT** is net-new DMA engine (mcdma 8.7k, HP0 SmartConnect 4.4k, GP0 control 0.5k,
demux+mux 0.4k) plus 3 BRAM36 + 4 BRAM18. Extrapolated onto rev_d_shim (22.3k LUT / 86
BRAM36 at 4 boards today), 8 boards + MCDMA lands at **~52-54k LUT (~97-102%)** -- LUT, not
BRAM, is the binding constraint, and this settled MCDMA over eight separate `axi_dma`. The
FIFOs shrink to elastic buffers there, freeing most of the BRAM. See `PROJECT_BRIEF`
sections 4 and 7.

## Design notes

Two `s2mm_mux` (`axis_switch`) settings are easy to get wrong and worth calling out:

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
  every channel round-trips byte-exact.

Other things worth knowing:

- `axi_cfg_register` width must be a multiple of 32. The core sizes its register file
  as `CFG_SIZE = CFG_DATA_WIDTH / AXI_DATA_WIDTH` (32), so a width below 32 integer-
  divides to zero storage: the generate loop instantiates no flip-flops and `cfg_data`
  ties off to 0, silently ignoring every write. `buf_reset` therefore uses a full 32-bit
  word (low `num_ch` bits) rather than a `num_ch`-bit register, and any new narrow cfg
  register must round its width up to 32.
- Flow control is `TREADY`, not fill-count. A full downstream FIFO stalls the MCDMA
  channel mid-descriptor; DMA overrun of a PL FIFO is not possible. Assert `TLAST` only
  at end-of-capture (per-sample `TLAST` makes tiny one-descriptor packets).
- TrustZone: PS peripherals default to secure; accesses with `AxPROT[1]=1` return
  `DECERR`. Check this first if transfers fail immediately.
- Don't use 32-bit HP mode, and remember the HP interface may reorder reads/writes
  (MCDMA handles it; a custom PL master must).
- 64-bit memory-map width handles odd-length streams cleanly. The descriptor's
  byte-granular `length` -- not the bus width -- sets how many 32-bit beats are
  emitted, so a 5-word (20-byte) command streams exactly 5 beats with `TLAST` on the
  5th; the DMA over-reads the final 64-bit word by up to 4 bytes and drops that tail
  internally (it never reaches the stream). Only the buffer **base** needs 8-byte
  alignment (cache-line alignment already covers it) and its **size** rounded up to an
  8-byte multiple so the tail over-read stays in-region. So the parent project keeps
  64-bit; no user-side pointer/alignment/garbage handling for odd-word DAC commands.

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
