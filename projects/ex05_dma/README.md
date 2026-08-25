***Updated 2026-08-25***

# Example 05: DDR-Backed FIFO Buffers via MCDMA

Example 05 builds a complete DMA data path between the PS (DDR) and the PL and uses it
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
  shared `cfg`/`sts` register pair (the ex03 `pl-reg` misc-device approach)
- Aggregating all per-channel MCDMA completion/error interrupts onto one non-root
  interrupt node (the `pl-irq` module) and taking completion as a blocking `read()`

> The datapath round-trips every channel byte-for-byte on hardware without root:
> `mcdma-loopback` passes for all channels and any subset, the per-channel
> `axi_rate_gen` pacer throttles and pauses each channel independently under `rate-ctl`,
> and `fault-inject` confirms the cache sync is load-bearing (skipping it silently
> corrupts every channel). A coordinated `halt -> clear -> reinit -> re-run` brings a
> channel back byte-exact after a mid-run FIFO clear (`halt-reset`), with `noclear`
> confirming the register-driven FIFO clear is load-bearing. The same transfer driven
> off the aggregated MCDMA interrupt through the `pl-irq` node (`dma-irq`) now completes
> interrupt-driven on hardware, all 8 channels byte-exact, with a first-completion latency
> around 0.07 ms. (An earlier bug programmed the per-channel interrupt enables at the AXI-DMA
> bit positions 12/13/14 instead of the AXI MCDMA's 5/6/7, so `introut` never asserted; the
> software fix corrected the bit layout.) `dma-bench` closes the last item: driving a real
> multi-descriptor SG ring, it measures throughput peaking at ~179 MB/s (~45% of the
> ~400 MB/s HP0/stream ceiling) with the knee at 256-beat chunks, a ~58 us software-polled
> per-transfer latency floor, and the derived worst-case per-channel service gap (see
> [Throughput and latency](#throughput-and-latency)).

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
3. What is the worst-case service latency? Interrupt-driven completion works: `dma-irq`
   blocks on the aggregated MCDMA interrupt through `pl-irq` and reports a sub-0.1 ms
   first-completion latency on hardware, with the `axi_rate_gen` pacer supplying controllable
   load. `dma-bench` adds the quantitative picture: throughput peaks at ~179 MB/s (~45% of
   ceiling) and knees at 256-beat chunks, where the derived worst-case per-channel service
   gap (~44 us) sizes the parent's DAC/ADC FIFOs (see
   [Throughput and latency](#throughput-and-latency)).
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
- `xlconcat` gathering the `2*num_ch` per-channel MCDMA completion/error interrupts,
  then a `util_reduced_logic` OR-reduction onto the single `IRQ_F2P[0]` line (GIC ID
  61, device tree `<0 29 4>`, level-high). The `pl-irq` module binds it and exposes it
  to userspace non-root as one aggregated doorbell, `/dev/mcdma_irq` (see
  [Device tree](#device-tree)) -- the rev_d_shim model of one error-alert IRQ plus a
  poll of the status word, rather than a GIC line per channel.
- A shared `axi_cfg_register` (`rate_cfg`) and `axi_sts_register` (`rate_sts`) on
  GP0 -- 32 control/status bits per channel -- backing the per-channel pacers
  (the ex02/ex03 `CFG -> logic -> STS` idiom). `pl-reg` publishes them non-root as
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
non-root register pattern as ex03's `reg-driver`, no root and no hardcoded addresses.
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

`software/dma-irq/dma-irq.c` runs the same prebuffered transfer as `mcdma-loopback` but
waits for completion on an interrupt instead of polling. It arms every channel with its
MCDMA completion and error interrupts enabled, then blocks in `poll()`/`read()` on the
`pl-irq` misc device (`/dev/mcdma_irq`). Because all `2*num_ch` channel interrupts are
OR-reduced onto one line, the interrupt is only a doorbell: on each wakeup the tool reads
every channel's MCDMA status register to see which completed or errored, clears those
write-1-to-clear status bits so the level-triggered line deasserts, and re-arms the
interrupt (`write()` of `1`, the `pl-irq` re-arm). Completion is taken from the
authoritative per-channel status register bit, not a re-read of the DDR descriptor (which
would race the descriptor writeback). It reports the first-completion notification latency
and verifies the byte-exact round trip. This is the ex05 measurement vehicle for the
parent project's single aggregated error-alert IRQ; rev_d_shim keeps the happy path polled
and uses the interrupt for exceptional events. (It works on hardware -- all channels
complete interrupt-driven byte-exact; see [section 9](#9-take-completion-on-an-interrupt).)

`pl-irq` is the interrupt sibling of `pl-reg`: an out-of-tree module
(`kernel_modules/pl-irq`) that binds the interrupt node by a private device-tree
compatible and publishes it as a world-accessible (`0666`) misc device named from the node
label. It needs no kernel command line change and no `chmod` -- see [Device tree](#device-tree).

`software/dma-bench/dma-bench.c` is the throughput/latency measurement tool. It reuses the
same register model, descriptor layout, and u-dma-buf mapping as `mcdma-loopback` but adds
the one capability the loopback never needed: a real **multi-descriptor scatter-gather
ring** -- `K` descriptors per channel, each a `<=1024`-beat SOF|EOF packet. That is the
correct shape for the packet-atomic `s2mm_mux` (many small packets, not one huge packet)
and de-risks the SG ring the parent project needs for continuous streaming. With no
arguments it runs the full suite: a correctness gate, a single-packet **per-transfer
latency** floor (min/mean/max), and a **chunk-size sweep** that holds total bytes per
channel fixed and reports, per chunk, sustained aggregate throughput, the derived
worst-case per-channel service gap, and the isolated single-packet latency. It times only
the engine (MM2S trigger to all-complete), discards the cold first iteration of every
measurement, and excludes the one-time `sync_for_*` CPU cost from throughput. See
[Throughput and latency](#throughput-and-latency).

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
the Vivado instance labels -- exactly the ex03 mechanism.

The `.dtsi` also adds the interrupt node (`mcdma_irq`, `interrupts = <0 29 4>`,
level-high) under `&amba_pl` for the OR-reduced MCDMA interrupt on `IRQ_F2P[0]`, with a
private `compatible = "zynq-toolbox,pl-irq"`. The out-of-tree `pl-irq` module binds it by
that compatible and publishes it as the world-accessible misc device `/dev/mcdma_irq` --
no kernel command line change and no `chmod`, the same ergonomics `pl-reg` gives register
windows. (ex04 uses this same `pl-irq` module for its interrupt lines, and documents
the in-tree `generic-uio` path there as the manual-maintenance alternative.)

## Build integration

A normal `make PROJECT=ex05_dma` produces an SD image where the block design (bitstream
+ `.xsa`) contains the MCDMA, the AXI4-Stream datapath, the per-channel rate
pacers, the per-channel FIFO reset, and the OR-reduced MCDMA interrupt, `u-dma-buf` and
the `pl-reg`/`pl-irq` modules are built out-of-tree from `kernel_modules/` and autoloaded,
the `boot_script.sh` chmod service is installed (by `scripts/petalinux/boot_script.sh`,
guarded by `scripts/check/boot_script.sh`), and `mcdma-loopback`, `rate-ctl`,
`fault-inject`, `halt-reset`, `dma-irq`, and `dma-bench` are cross-compiled into the
rootfs. No kernel command line change is needed -- `pl-irq` binds the interrupt node by its
device-tree compatible.

## Trying it on hardware

After `make PROJECT=ex05_dma`, write the SD image, boot, and log in. Run the commands
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

### 9. Take completion on an interrupt

```sh
dma-irq
```

Same prebuffered transfer as `mcdma-loopback`, but instead of polling the descriptors it
blocks on the aggregated MCDMA interrupt through the `pl-irq` node. All eight channels
round-trip byte-exact, and completion arrives as a real interrupt (a non-zero count and a
sub-millisecond first-completion latency):

```
dma-irq: 8-channel prebuffered MCDMA transfer, completion via pl-irq

PL interrupt: /dev/mcdma_irq (pl-irq, no root)
MCDMA control: /dev/mcdma (pl-reg, no root)
u-dma-buf udmabuf0: phys 0x30000000, 36864 bytes used of 4194304

  ch0  ok    received 2048/2048 bytes
  ...
  ch7  ok    received 2048/2048 bytes

interrupts: 2;  first-completion latency 0.065 ms
All channels completed and round-tripped (interrupt-driven).
```

Getting here took one fix. The aggregated interrupt originally never reached userspace:
`/proc/interrupts` for `pl-irq` (`47: ... GIC-0 61 Level pl-irq`) stayed at `0` across a run,
so `introut` never asserted at the GIC, even though the data transferred correctly. That
exonerated `pl-irq` (its DT binding, IRQ mapping, and misc device are all correct) and put
the fault in the MCDMA interrupt programming: `dma-irq` had enabled the per-channel
completion/error interrupts at the *AXI-DMA* bit positions (`CR`/`SR` bits 12/13/14), but the
AXI **MCDMA** puts its per-channel interrupt enables and status at bits 5/6/7
(`XILINX_MCDMA_IRQ_IOC/DELAY/ERR_MASK` in `drivers/dma/xilinx/xilinx_dma.c`; only the
completion threshold at bits [23:16] is shared). Writing 12/14 left the real enables clear,
so the IP never drove `introut`, and reading status bit 14 as "error" was a misread of a
normal transfer. Correcting those six bit definitions in `software/dma-irq/dma-irq.c` -- a
software-only change, since these are software-written IP registers -- makes the interrupt
assert and clears the spurious error. `pl-irq`'s userspace path is independently validated
in the ex04 interrupts example against a known-good, MCDMA-free interrupt source.

### 10. Measure throughput and latency

```sh
dma-bench
```

`dma-bench` drives a real multi-descriptor SG ring (`K` `<=1024`-beat packets per channel)
and reports the four sizing metrics in one run: it first gates on a verified all-channel
round trip, then prints a single-packet latency floor and a chunk-size sweep. Each row of
the sweep holds total bytes per channel fixed and reports sustained aggregate throughput
(all 8 channels full rate), the derived worst-case per-channel service gap, and the
isolated single-packet latency at that chunk size. Expect throughput to climb with chunk
size while the service gap and per-packet latency shrink -- the smaller-chunk /
shallower-FIFO vs. larger-chunk / higher-throughput tradeoff the parent picks the knee of:

```
dma-bench: 8-channel MCDMA throughput / latency benchmark

MCDMA control: /dev/mcdma (pl-reg, no root)
u-dma-buf udmabuf0: phys 0x30000000, 1572864 bytes used of 4194304

correctness: all 8 channels round-tripped (256-beat chunks, k=64)

per-transfer latency (single 64-beat packet, 1 channel, 64 runs):
  min 57.0 us   mean 59.6 us   max 77.0 us

chunk sweep (16384 words/channel fixed, all channels full rate):
  chunk(beats)  desc/ch  throughput(MB/s)  gap(us)  latency(us)
          32      512              54.4    16.48         59.0
          64      256             100.4    17.85         57.0
         128      128             152.6    23.49         58.0
         256       64             161.1    44.50         58.0
         512       32             177.2    80.92         58.0
        1024       16             178.6   160.56         58.0

HP0 payload ceiling ~= 400 MB/s (64-bit @ 100 MHz, /2 for MM2S+S2MM)
best measured 178.6 MB/s (45% of ceiling)
```

Throughput climbs steeply through 128 beats and then knees; the `latency` column is flat at
~58 us because software-polled completion pins it to the poll syscall floor, not the
sub-microsecond engine time (the interrupt path, `dma-irq`, shows a comparable sub-0.1 ms
notification latency). The worst-case gap is derived from the packet-atomic round-robin
model -- `(num_ch - 1)` packets of service time between a channel's windows -- not a
per-packet hardware timestamp, which software polling is too coarse to capture.
[Throughput and latency](#throughput-and-latency) reads the sweep (the knee lands at
256-beat chunks) and what it means for sizing.
means for sizing.

## What's left

Nothing blocking. The DMA datapath is fully proven on hardware: prebuffered transfers,
independent per-channel rates, coherency safety, coordinated halt/clear/reset,
interrupt-driven completion through `pl-irq`, and the `dma-bench` throughput/latency
measurements ([Throughput and latency](#throughput-and-latency)) all pass, closing every
open question in [Why this example exists](#why-this-example-exists). What remains is on the
parent side: folding these numbers into rev_d_shim's chunk-size and FIFO-depth choices (see
[Throughput and latency](#throughput-and-latency)).

## Throughput and latency

`dma-bench` (`software/dma-bench/dma-bench.c`) measures what the MCDMA actually delivers, so
the parent project can size FIFOs and pick a chunk size rather than rely on the ~20x
bandwidth-margin estimate (`PROJECT_BRIEF` section 6). It is the one tool here that builds a
real **multi-descriptor SG ring** -- `K` descriptors per channel, each a `<=1024`-beat
SOF|EOF packet -- which is both the correct shape for the packet-atomic `s2mm_mux` (many
small packets, never one packet past the 1024-beat `ARB_ON_MAX_XFERS` backstop) and the SG
ring shape the parent needs for continuous streaming. `mcdma-loopback` stays the clean
single-descriptor integrity checker.

Four metrics, all from one `dma-bench` run:

- **Sustained aggregate throughput** -- total payload bytes / engine-busy time, all 8
  channels at full rate. The ceiling is roughly HP0 bandwidth / 2: HP0 is 64-bit at `FCLK`
  (800 MB/s) and loopback crosses it twice (MM2S read + S2MM write), so ~400 MB/s of payload.
- **Per-transfer latency** -- start to completion for one small single-descriptor packet,
  min/mean/max over many runs: the descriptor-fetch + engine + writeback floor. Because
  `dma-bench` polls for completion, this floor also includes the poll syscall cost (~58 us
  measured); the true interrupt-notification latency is the sub-0.1 ms `dma-irq` reports.
- **Overhead vs. chunk size** -- throughput swept over beats-per-descriptor with total bytes
  per channel held fixed so the points are comparable. Small chunks add per-packet overhead;
  larger chunks (up to the 1024-beat backstop) amortize it.
- **Worst-case per-channel service gap** -- with all 8 channels loaded full-rate, the longest
  a single channel waits between its service windows. The `s2mm_mux` is packet-atomic
  round-robin, so a channel waits while the other seven are each serviced one packet:
  `gap = (num_ch - 1) * (engine-busy / total-packets)`. This sets the minimum ADC/DAC FIFO
  depth in the parent. It is derived from the round-robin model, not a per-packet hardware
  timestamp -- software polling is far too coarse to time a sub-microsecond packet directly.

Methodology: the cold first iteration of every measurement is discarded and steady state
reported; only the engine work (MM2S trigger to all-complete) is timed, so the one-time
`sync_for_*` CPU cost is excluded from throughput; the throughput and gap runs are at full
rate (the `axi_rate_gen` pacer transparent) so data is always available -- the true worst
case for arbitration.

The headline is the chunk-size sweep: smaller chunks shorten the service gap (shallower
FIFOs) but cost throughput; larger chunks do the reverse, so the parent picks the knee.
Measured on hardware (representative run; consistent across runs to within ~2%):

| chunk (beats) | descriptors/ch | throughput (MB/s) | worst-case gap (us) | latency (us) |
|---|---|---|---|---|
| 32 | 512 | 54 | 16.5 | 58 |
| 64 | 256 | 100 | 17.9 | 58 |
| 128 | 128 | 151 | 23.5 | 58 |
| 256 | 64 | 162 | 44.5 | 58 |
| 512 | 32 | 177 | 80.9 | 58 |
| 1024 | 16 | 179 | 160.6 | 58 |

Throughput climbs steeply through 128 beats and then knees. 256-beat chunks (1 KiB packets)
already reach ~162 MB/s at a bounded ~44 us worst-case gap; doubling the chunk to 512 or
1024 beats buys only ~10% more throughput (~179 MB/s peak) while doubling the service gap
each step (~44 -> ~81 -> ~161 us), and with it the per-channel FIFO depth the parent must
provision. So **256-beat chunks are the practical operating point** -- near-peak throughput
at a bounded gap. The peak ~179 MB/s is ~45% of the ~400 MB/s ceiling; the shortfall is SG
descriptor-fetch traffic sharing HP0 plus the packet-atomic mux serializing all 8 channels
through the single 32-bit S2MM stream with an arbitration bubble per packet. The `latency`
column is flat at ~58 us -- software-polled completion pins it to the poll syscall floor,
not the sub-microsecond engine time -- so treat it as a polling floor, not the engine's
transfer latency. Even the smallest measured throughput clears the parent's requirement
comfortably (the ~20x-margin estimate holds).

The table is fixed at 16384 words/channel (64 KiB) per direction; the u-dma-buf region uses
~1.5 MiB of its 4 MiB for descriptors + payload. To re-measure, boot the ex05 image and run
`dma-bench` (no arguments); it prints the sample output shown in
[section 10](#10-measure-throughput-and-latency).

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

- [ex04](../ex04_interrupts/README.md) -- delivering PL interrupts to userspace non-root
  via `pl-irq`; the DMA completion interrupts reuse this.
- [ex03](../ex03_device_driver/README.md) -- reaching PL registers via a non-root misc
  driver (`pl-reg`); the MCDMA control window reuses this pattern.
- `PROJECT_BRIEF.md` -- the parent project this example de-risks, including the
  reasoning behind choosing MCDMA and the prebuffered model.
- UG585 (Zynq-7000 TRM), AXI_HP Interfaces chapter -- port behavior, FIFO depths,
  reordering, and the performance optimization summary.
- PG288 -- AXI MCDMA product guide. PG021 -- AXI DMA, for comparison.

---

Previous: [Example 04: Interrupts](../ex04_interrupts/README.md) | Next: [Example 06: UART](../ex06_uart/README.md)
