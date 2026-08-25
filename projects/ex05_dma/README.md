***Updated 2026-08-25***

# Example 05: DDR-Backed FIFO Buffers via MCDMA

Example 05 builds a full DMA data path between the PS (DDR) and the PL and uses it to give a set of shallow PL FIFOs a large backing store in DDR. The PS preloads long buffers into DDR ahead of time, an AXI MCDMA engine feeds them into on-chip FIFOs on demand, and drains PL-produced data back to DDR far faster than the PS could move it register-by-register. `num_ch` MM2S and `num_ch` S2MM channels (default 8) run independently, each bound to its own FIFO and addressed by `TDEST` -- so the point is independent channels in flight at once, not raw throughput.

This is by far the most involved example, but it's built entirely from pieces the earlier ones introduced: the MCDMA control window and the per-channel rate registers are reached non-root through the ex03 `pl-reg` driver, and the aggregated completion interrupt is delivered non-root through the ex04 `pl-irq` module. What's new is the DMA engine itself, the DDR-backed prebuffered model, and the streaming datapath that routes each channel to its own FIFO.

The project introduces the following tools and concepts:
- Driving an AXI MCDMA with independent per-channel scatter-gather rings
- Using DDR as a large FIFO backing store (the prebuffered playback/capture model)
- Physically contiguous DMA buffers with `u-dma-buf`, plus explicit cache sync
- Non-root MCDMA register access through a `pl-reg` node
- `TDEST` routing and `TLAST` packet semantics across a demux -> FIFO -> mux datapath
- Packet-atomic `axis_switch` arbitration (`ARB_ON_TLAST`) to merge streams `num_ch -> 1`
- A programmable-rate PL pacer (`axi_rate_gen`) between the FIFOs, controlled non-root through a shared `cfg`/`sts` register pair
- Aggregating every per-channel MCDMA completion/error interrupt onto one non-root node (`pl-irq`) and taking completion as a blocking `read()`

## Block design

`block_design.tcl` is the source of truth; this is the shape of it. Everything is clocked at 100 MHz off `FCLK_CLK0`, and the channel count is the Tcl parameter `num_ch` (default 8).

The PS exposes two ports: HP0 (64-bit, the path to DDR carrying both payload and scatter-gather descriptor fetches) and GP0 (the MCDMA `S_AXI_LITE` control window plus the small register cores). An `axi_mcdma` provides `num_ch` MM2S and `num_ch` S2MM channels with scatter-gather enabled, a 64-bit memory-map width matching HP0, and its buffer-length register widened to 23 bits so a multi-MB transfer is a single descriptor rather than a 16 KB-capped chain. Two `smartconnect`s carry the traffic: one for GP0 -> control, and one aggregating the MCDMA's three memory masters (MM2S, S2MM, SG) onto `S_AXI_HP0`. Addresses are assigned explicitly with `addr`, per repo convention.

Between MM2S and S2MM, each channel gets its own DAC and ADC FIFO:

```
M_AXIS_MM2S -> mm2s_demux -> dac_fifo[i] -> rate_gen[i] -> adc_fifo[i] -> s2mm_mux -> S_AXIS_S2MM
               (axis_switch,                (rate pacer)                 (axis_switch,
                1 -> num_ch by TDEST)                                     num_ch -> 1)
```

This mirrors rev_d_shim, where a SPI core sits in the gap between the two FIFOs. Here that gap holds `axi_rate_gen`, a small custom core that forwards the stream unchanged (`TDEST`/`TLAST` preserved) but throttles it to a per-channel programmed rate and can pause it -- standing in for the SPI core's pacing. `TDEST == i` is preserved end to end, so MCDMA S2MM routes each channel's data back to itself. The `num_ch -> 1` recombine is a stock `axis_switch` set to arbitrate packet-atomically (`ARB_ON_TLAST`): it grants one input and holds it through `TLAST` before advancing, so packets are never interleaved and no channel starves (this needs `HAS_TLAST` set explicitly -- see the [design notes](#appendix-design-notes)).

Three small register cores on GP0 round it out, all published non-root by `pl-reg` from their Vivado instance labels: an `axi_cfg_register`/`axi_sts_register` pair (`rate_cfg`/`rate_sts`) backing the per-channel pacers, and an `axi_cfg_register` (`buf_reset`) whose bits each clear one channel's DAC/ADC FIFO for the coordinated reset path. The `2*num_ch` MCDMA completion/error interrupts are gathered by an `xlconcat` and OR-reduced onto the single `IRQ_F2P[0]` line, which `pl-irq` exposes as one aggregated interrupt at `/dev/mcdma_irq` -- the rev_d_shim model of one error-alert IRQ plus a poll of the status word, rather than a GIC line per channel.

## Software

The programs under `software/` all reach registers non-root through `pl-reg` and use `u-dma-buf` for DMA memory. The prebuffered model they share -- fill DDR ahead of time, then let the engine run with no software in the loop -- is the parent project's real usage, and the one where scheduling jitter cannot cause an underrun.

- `mcdma-loopback` is the core integrity checker. It maps the MCDMA control window (`/dev/mcdma`, or `/dev/mem` as a root fallback), carves one `u-dma-buf` region into an SG descriptor area plus a src/dst payload pair per channel, `sync_for_device` once, starts every channel, polls each S2MM descriptor for completion, `sync_for_cpu`, and verifies the byte-exact round trip. Pass channel indices to run a subset; no args runs all.
- `rate-ctl` programs and reads back the per-channel `axi_rate_gen` pacers through `/dev/rate_cfg` and `/dev/rate_sts` -- set a rate, run traffic, read the beat counts back.
- `fault-inject` proves the cache sync is load-bearing: a baseline run syncs normally, while `fault-inject nosync` skips the payload `sync_for_device` so the MCDMA reads stale DDR and every channel completes with full length but all-zero data -- silent corruption a content check catches.
- `halt-reset` exercises the DMA's only fault/shutdown response: an ordered halt -> clear FIFOs (`buf_reset`) -> reinit rings -> re-run. `halt-reset noclear` skips the clear so stranded data corrupts the re-run, showing the clear is required.
- `dma-irq` runs the same transfer but blocks on the aggregated interrupt through `pl-irq` instead of polling, and reports the first-completion latency.
- `dma-bench` measures throughput and latency over a real multi-descriptor SG ring (see [Throughput and latency](#appendix-throughput-and-latency)).
- `xilinx-dma-test` is superseded (it drove a plain `axi_dma` in direct-register mode) and kept only as a register-model reference.

`u-dma-buf` exposes its `/dev/udmabuf0` mmap node (`0600`) and sysfs cache-sync controls (`0664`) root-owned with no mode knob, so the project's `boot_script.sh` `chmod`s both to `0666` at boot (installed as an `/etc/init.d` service; this rootfs has no udev). Prebuffered mode needs only one `sync_for_device` before a run and one `sync_for_cpu` after, on a cached mapping so filling multi-MB patterns stays fast.

## Device tree

`cfg/.../petalinux/<ver>/device_tree.dtsi` declares three things:

- a `reserved-memory` region (4 MiB at `0x30000000`, base and size both 4 MiB-aligned) that `u-dma-buf` claims as `/dev/udmabuf0`;
- a `compatible` override on the MCDMA node to a private `zynq-toolbox,mcdma-userspace`, so no in-kernel driver matches and `pl-reg` claims it deterministically as `/dev/mcdma` (PetaLinux otherwise tags a standalone MCDMA as `xlnx,eth-dma`);
- the interrupt node (`mcdma_irq`, `interrupts = <0 29 4>`, level-high, `compatible = "zynq-toolbox,pl-irq"`) for the OR-reduced MCDMA interrupt on `IRQ_F2P[0]`, which `pl-irq` publishes as `/dev/mcdma_irq`.

The `rate_cfg`/`rate_sts`/`buf_reset` windows need no entry -- PetaLinux auto-generates their nodes and `pl-reg` binds them by their cfg/sts compatibles, exactly the ex03 mechanism.

## Trying it on hardware

After `make PROJECT=ex05_dma`, write the SD image, boot, and log in. Everything below runs as an ordinary user.

First confirm the driver nodes came up non-root:

```sh
dmesg | grep pl-reg      # one "mode 0666" line per window
ls -l /dev/mcdma /dev/rate_cfg /dev/rate_sts /dev/buf_reset /dev/udmabuf0
```

All five should be present and world-accessible (`crw-rw-rw-`). A missing `/dev/udmabuf0` means the `reserved-memory` node didn't take (check `dmesg` -- CMA failures are quiet); a missing `/dev/mcdma` means the `compatible` override didn't apply, and the program falls back to `/dev/mem` under `sudo`.

Then exercise the datapath:

```sh
mcdma-loopback       # every channel round-trips byte-exact ("ok")
rate-ctl             # read per-channel rate_div/pause and beat_count
rate-ctl set 2 15    # throttle channel 2; mcdma-loopback still passes, just slower
rate-ctl pause 3     # channel 3 alone stalls: its S2MM times out with an all-zero dst
rate-ctl run 3       # channel 3 resumes; mcdma-loopback passes again
```

The pacer only throttles or pauses -- it never corrupts -- so a throttled channel simply takes longer and a paused one backpressures only itself. Run a single channel (`mcdma-loopback 0`) to watch its `elapsed` time scale with its rate.

Finally, the correctness and measurement tools:

```sh
fault-inject         # baseline: every channel ok (PASS)
fault-inject nosync  # skips the payload sync: every channel corrupt (still PASS -- that's the expected outcome)
halt-reset           # halt -> clear -> reinit -> re-run: every channel ok
halt-reset noclear   # skips the FIFO clear: the re-run corrupts, proving the clear is needed
dma-irq              # same transfer, completion via the pl-irq interrupt
dma-bench            # throughput / latency sweep (see appendix)
```

If a transfer fails immediately with no data, suspect the TrustZone `DECERR` gotcha in the [design notes](#appendix-design-notes). If you get `Permission denied`, the boot script didn't run -- check `/etc/init.d/boot-script` and fall back to `sudo`.

## Appendix: Throughput and latency

`dma-bench` (`software/dma-bench/dma-bench.c`) measures what the MCDMA actually delivers, so the parent project can size FIFOs and pick a chunk size instead of guessing. Unlike the single-descriptor `mcdma-loopback`, it drives a real multi-descriptor scatter-gather ring (`K` descriptors per channel, each a `<=1024`-beat SOF|EOF packet) -- the correct shape for the packet-atomic `s2mm_mux` and the SG ring the parent needs for continuous streaming. One run reports four metrics:

- Sustained aggregate throughput -- payload bytes / engine-busy time, all channels at full rate. The ceiling is roughly HP0 bandwidth / 2 (64-bit at 100 MHz is 800 MB/s, crossed twice for MM2S read + S2MM write), so ~400 MB/s of payload.
- Per-transfer latency -- start to completion for one small packet. Because `dma-bench` polls, this floor (~58 us) is dominated by the poll syscall, not the engine; the interrupt path (`dma-irq`) reports a sub-0.1 ms notification latency.
- Overhead vs. chunk size -- throughput swept over beats-per-descriptor with total bytes held fixed. Small chunks add per-packet overhead; larger chunks amortize it, up to the 1024-beat arbitration backstop.
- Worst-case per-channel service gap -- with all channels loaded, the longest one waits between its service windows. The mux is packet-atomic round-robin, so `gap = (num_ch - 1) * (engine-busy / total-packets)`. This sets the minimum ADC/DAC FIFO depth in the parent. It's derived from the round-robin model, since software polling is too coarse to time a sub-microsecond packet directly.

The headline is the chunk-size sweep -- smaller chunks shorten the service gap (shallower FIFOs) but cost throughput, so the parent picks the knee. A representative hardware run (16384 words/channel per direction, consistent to within ~2%):

| chunk (beats) | descriptors/ch | throughput (MB/s) | worst-case gap (us) | latency (us) |
|---|---|---|---|---|
| 32 | 512 | 54 | 16.5 | 58 |
| 64 | 256 | 100 | 17.9 | 58 |
| 128 | 128 | 151 | 23.5 | 58 |
| 256 | 64 | 162 | 44.5 | 58 |
| 512 | 32 | 177 | 80.9 | 58 |
| 1024 | 16 | 179 | 160.6 | 58 |

Throughput climbs steeply through 128 beats and then knees. 256-beat chunks (1 KiB packets) already reach ~162 MB/s at a bounded ~44 us gap; doubling the chunk buys only ~10% more throughput while doubling the gap each step, so 256-beat chunks are the practical operating point. The ~179 MB/s peak is ~45% of the ~400 MB/s ceiling, the shortfall being SG descriptor traffic sharing HP0 plus the mux serializing all channels through the single 32-bit S2MM stream. Re-measure any time by booting the ex05 image and running `dma-bench` with no arguments.

## Appendix: Utilization

Synthesized at 8+8 (16 streams, the rev_d_shim size) for `xc7z020-3` (Vivado 2024.2), the whole example is 15,089 LUT / 15,691 FF / 19 BRAM36 + 4 BRAM18 / 0 DSP. Of that, ~13.9k LUT is net-new DMA engine (mcdma 8.7k, HP0 SmartConnect 4.4k, GP0 control 0.5k, demux + mux 0.4k) plus 3 BRAM36 + 4 BRAM18. Extrapolated onto rev_d_shim (22.3k LUT / 86 BRAM36 at 4 boards), 8 boards plus MCDMA lands around 52-54k LUT (~97-102% of the 7020) -- so LUT, not BRAM, is the binding constraint, which is what settled MCDMA over eight separate `axi_dma`. The channel count is the one Tcl parameter `num_ch`, so re-synthesizing at a different size is a one-line change; the numbers come from the post-synth hierarchical utilization report under `tmp_reports/`.

## Appendix: Design notes

The two `s2mm_mux` (`axis_switch`) settings that are easy to get wrong:

- `axis_switch` TDEST windows take hex. The demux's per-MI `BASETDEST`/`HIGHTDEST` are `bitString` params: pass `[format 0x%08X $i]`, not a bare integer, or the derived array modelparam rejects any value needing more than one bit (0 and 1 slip through, which hides it until `num_ch >= 3`). A single-MI switch also defaults to the window `[0,0]` and silently drops higher channels, so a mux MI's window must span `[0, num_ch-1]`.
- The S2MM recombine needs packet-atomic arbitration. A stock `axis_switch` re-arbitrates per beat, interleaving channels onto the single S2MM stream; since MCDMA latches `TDEST` at start-of-packet, the mix lands on one channel and the rest starve. It arbitrates on packet boundaries with `ARB_ON_TLAST`, but only if `HAS_TLAST` is set explicitly -- left to propagation the tool silently drops `ARB_ON_TLAST` back to 0.

Other gotchas worth knowing:

- `axi_cfg_register` width must be a multiple of 32. The core sizes its register file as `CFG_DATA_WIDTH / 32`, so a narrower width divides to zero storage and silently ignores writes. `buf_reset` therefore uses a full 32-bit word (low `num_ch` bits), and any new narrow cfg register must round up to 32.
- Flow control is `TREADY`, not fill-count: a full downstream FIFO stalls the MCDMA mid-descriptor, so a DMA overrun of a PL FIFO isn't possible. Assert `TLAST` only at end-of-capture.
- TrustZone: PS peripherals default to secure, and an access with `AxPROT[1]=1` returns `DECERR`. Check this first if transfers fail immediately.
- Keep the 64-bit HP memory-map width (don't use 32-bit mode). It handles odd-length streams cleanly: the descriptor's byte-granular length sets the beat count, so a 5-word command streams exactly 5 beats with `TLAST` on the fifth and the DMA drops the internal tail over-read. Only the buffer base needs 8-byte alignment (cache-line alignment covers it), with its size rounded up to an 8-byte multiple.

## Reference notes

- [ex03](../ex03_device_driver/README.md) -- reaching PL registers non-root via the `pl-reg` misc driver, which the MCDMA control and rate windows reuse.
- [ex04](../ex04_interrupts/README.md) -- delivering PL interrupts to userspace non-root via `pl-irq`, which the aggregated DMA completion interrupt reuses.
- UG585 (Zynq-7000 TRM), AXI_HP Interfaces chapter -- HP port behavior, FIFO depths, and reordering.
- PG288 (AXI MCDMA) and PG021 (AXI DMA, for comparison).

---

Previous: [Example 04: Interrupts](../ex04_interrupts/README.md) | Next: [Example 06: UART](../ex06_uart/README.md)
