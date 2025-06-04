# SPI Configuration Synchronization Core

The `spi_cfg_sync` module synchronizes configuration signals from the AXI (PS) clock domain to the SPI clock domain.

## Inputs and Outputs

### Inputs

- **Clocks and Reset**
  - `aclk`: AXI (PS) clock signal.
  - `spi_clk`: SPI clock signal.
  - `spi_resetn`: Active-low reset signal for the SPI domain.

- **AXI Domain Configuration Inputs**
  - `trig_lockout [31:0]`: Trigger lockout configuration.
  - `integ_thresh_avg [14:0]`: Integration threshold average configuration.
  - `integ_window [31:0]`: Integration window configuration.
  - `integ_en`: Integration enable signal.
  - `spi_en`: SPI enable signal.

### Outputs

- **SPI Domain Synchronized Outputs**
  - `trig_lockout_stable [31:0]`: Synchronized and stable trigger lockout configuration.
  - `integ_thresh_avg_stable [14:0]`: Synchronized and stable integration threshold average.
  - `integ_window_stable [31:0]`: Synchronized and stable integration window configuration.
  - `integ_en_stable`: Synchronized and stable integration enable signal.
  - `spi_en_stable`: Synchronized and stable SPI enable signal.

## Operation

- Each input signal from the AXI domain is synchronized to the SPI clock domain using a 3-stage synchronizer with a stability check.
- For each signal, a stability flag is generated to indicate when the synchronized value is stable.
- When all stability flags are asserted and `spi_en_sync` is high, the synchronized values are latched into the corresponding stable output registers.
- On SPI domain reset (`spi_resetn` low), all stable output registers are cleared to their default values (zeros).
