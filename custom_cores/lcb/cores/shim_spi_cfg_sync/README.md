***Updated 2024-08-01***
# SPI Configuration Synchronization Core

The `shim_spi_cfg_sync` module synchronizes configuration signals from the AXI clock domain to the SPI clock domain.

## Inputs and Outputs

### Inputs

- **Clocks and Reset**
  - `aclk`: AXI domain clock signal.
  - `aresetn`: Active-low reset for AXI domain.
  - `spi_clk`: SPI domain clock signal.
  - `spi_resetn`: Active-low reset for SPI domain.

- **AXI Domain Configuration Inputs**
  - `integ_thresh_avg [14:0]`: Integration threshold average configuration.
  - `integ_window [31:0]`: Integration window configuration.
  - `integ_en`: Integration enable signal.
  - `spi_en`: SPI enable signal.
  - `block_buffers`: Block buffers enable signal.

### Outputs

- **SPI Domain Synchronized Outputs**
  - `integ_thresh_avg_sync [14:0]`: Synchronized integration threshold average.
  - `integ_window_sync [31:0]`: Synchronized integration window.
  - `integ_en_sync`: Synchronized integration enable.
  - `spi_en_sync`: Synchronized SPI enable.
  - `block_buffers_sync`: Synchronized block buffers enable.

## Operation

- Each AXI domain input is synchronized to the SPI clock domain using the `sync_coherent` module.
- Default values are provided for each output in case of reset:
  - `integ_thresh_avg_sync`: 0x1000
  - `integ_window_sync`: 0x00010000
  - `integ_en_sync`: 0
  - `spi_en_sync`: 0
  - `block_buffers_sync`: 1

## Notes

- The `sync_coherent` module is used for each configuration signal to handle clock domain crossing.
- For more details, refer to the Verilog source code.
