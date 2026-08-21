# axi_rate_gen

Per-channel AXI4-Stream rate limiter for ex07's DAC -> ADC datapath. It sits
between a channel's DAC FIFO (`M_AXIS`) and ADC FIFO (`S_AXIS`) -- where the SPI
core lives in rev_d_shim -- and forwards beats unchanged (`tdata`/`tdest`/`tlast`
preserved, so TDEST routing and packet boundaries survive) while throttling the
stream to a programmed rate and optionally pausing it. Downstream backpressure
still propagates through it.

Control and status are one 32-bit word per channel, driven by slices of a shared
`axi_cfg_register` / `axi_sts_register` in the block design and reachable
non-root via `pl-reg` (see ex05).

| Word | Bits | Field | Meaning |
|------|------|-------|---------|
| `cfg` | `RATE_WIDTH-1:0` | `RATE_DIV` | extra idle cycles between beats (0 = full rate, N = one beat every N+1 cycles) |
| `cfg` | 16 | `PAUSE` | freeze forwarding while set |
| `sts` | 31:0 | `BEAT_COUNT` | saturating count of beats forwarded since reset |

## Parameters

- `DATA_WIDTH` (32) -- AXIS `tdata` width.
- `DEST_WIDTH` (8) -- AXIS `tdest` width.
- `RATE_WIDTH` (16) -- width of the `RATE_DIV` field / rate counter.

## Tests

```bash
./scripts/make/test_core.sh ex07_dma base axi_rate_gen
```
