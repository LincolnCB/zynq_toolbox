# Example 05: DDR-Backed FIFO Buffers via MCDMA

This image ships several userspace programs that drive and measure the MCDMA data path, all already built and on your `PATH`. They reach the MCDMA and pacer registers through `pl-reg` nodes and use `u-dma-buf` for DMA memory; the project's boot script relaxes both to world-accessible, so none of these need root. Most take an optional channel list or a mode word -- run each with no arguments for its default behavior.

## `mcdma-loopback`

The core round-trip test: preloads DDR buffers, runs every channel through the demux -> FIFO -> mux datapath, and verifies the byte-exact round trip. Run all channels, or pass indices for a subset:

```sh
mcdma-loopback         # all channels
mcdma-loopback 0 2     # just channels 0 and 2
```

## `rate-ctl`

Programs and reads back the per-channel `axi_rate_gen` pacers (`/dev/rate_cfg`, `/dev/rate_sts`). Set per-channel rates, run `mcdma-loopback` to push traffic, then read the beat counts back to confirm each channel advanced.

## `fault-inject`

Checks that the cache sync before a transfer is load-bearing. With no argument it runs a correct baseline (every channel `ok`); with `nosync` it skips the payload flush, so the engine reads stale data and every channel comes back corrupt:

```sh
fault-inject           # baseline, expect PASS
fault-inject nosync    # inject corruption, expect the FAIL it checks for
```

## `halt-reset`

Exercises the ordered halt -> clear -> reinit -> re-run recovery path. With no argument it runs the full sequence (byte-exact after the clear); with `noclear` it skips the FIFO clear, so stale data corrupts the re-run:

```sh
halt-reset             # full sequence
halt-reset noclear     # skip the clear, expect corruption
```

## `dma-irq`

The same round trip as `mcdma-loopback`, but it blocks on the aggregated MCDMA completion interrupt (`/dev/mcdma_irq`) instead of polling, and reports the first-completion latency.

## `dma-bench`

Throughput and latency measurement over a real multi-descriptor scatter-gather ring: a correctness gate, a per-transfer latency floor, and a chunk-size sweep reporting sustained throughput.

## `xilinx-dma-test`

Superseded -- kept only as a plain `axi_dma` direct-register reference, not part of the normal flow.
