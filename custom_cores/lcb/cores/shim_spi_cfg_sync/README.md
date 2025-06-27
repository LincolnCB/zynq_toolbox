***Updated 2025-06-18***
# SPI Configuration Synchronization Core

The `shim_spi_cfg_sync` module synchronizes configuration signals from the AXI clock domain to the SPI clock domain, ensuring reliable transfer and stable updates of configuration values.

## Inputs and Outputs

### Inputs

- **Clocks and Reset**
  - `spi_clk`: SPI clock signal.
  - `sync_resetn`: Active-low reset signal for the synchronization logic.

- **AXI Domain Configuration Inputs**
  - `integ_thresh_avg [14:0]`: Integration threshold average configuration.
  - `integ_window [31:0]`: Integration window configuration.
  - `integ_en`: Integration enable signal.
  - `spi_en`: SPI enable signal.
  - `block_buffers`: Block buffers enable signal.

### Outputs

- **SPI Domain Synchronized Outputs**
  - `integ_thresh_avg_stable [14:0]`: Synchronized and stable integration threshold average.
  - `integ_window_stable [31:0]`: Synchronized and stable integration window configuration.
  - `integ_en_stable`: Synchronized and stable integration enable signal.
  - `spi_en_stable`: Synchronized and stable SPI enable signal.
  - `block_buffers_stable`: Synchronized and stable block buffers enable signal.

## Operation

- Each AXI domain input is synchronized to the SPI clock domain using a 3-stage synchronizer with a stability check (`STABLE_COUNT=2`).
- Each synchronizer generates a stability flag indicating when the synchronized value is stable.
- When all configuration stability flags are asserted and `spi_en_sync` is high, the synchronized values are latched into the corresponding stable output registers.
- The `block_buffers_stable` output is updated independently when its stability flag is asserted.
- On synchronization reset (`sync_resetn` low), all stable output registers are cleared to their default values:
  - `integ_thresh_avg_stable`: 0
  - `integ_window_stable`: 0
  - `integ_en_stable`: 0
  - `spi_en_stable`: 0
  - `block_buffers_stable`: 1
