# SPI Configuration Synchronization Core

The `spi_cfg_sync` module ensures synchronization of configuration signals between the PS clock domain and the SPI clock domain. It operates as follows:

- **Inputs and Outputs**:
  - **Inputs**:
    - `clk`: PS clock signal.
    - `spi_clk`: SPI clock signal.
    - `rst`: Reset signal (active high).
    - `trig_lockout`: 32-bit input signal for trigger lockout configuration.
    - `cal_offset`: 16-bit input signal for calibration offset.
    - `dac_divider`: 16-bit input signal for DAC divider configuration.
    - `integ_thresh_avg`: 16-bit input signal for integration threshold average.
    - `integ_window`: 32-bit input signal for integration window configuration.
    - `integ_en`: Input signal to enable integration.
    - `spi_en`: Input signal to enable SPI synchronization.
  - **Outputs**:
    - `trig_lockout_stable`: 32-bit synchronized and stable trigger lockout configuration.
    - `cal_offset_stable`: 16-bit synchronized and stable calibration offset.
    - `dac_divider_stable`: 16-bit synchronized and stable DAC divider configuration.
    - `integ_thresh_avg_stable`: 16-bit synchronized and stable integration threshold average.
    - `integ_window_stable`: 32-bit synchronized and stable integration window configuration.
    - `integ_en_stable`: Synchronized and stable integration enable signal.
    - `spi_en_stable`: Synchronized and stable SPI enable signal.

- **Operation**:
  - Each input signal is synchronized to the SPI clock domain using a 3-stage synchronizer.
  - Stability flags are generated for each signal to indicate when the synchronized value is stable.
  - When all signals are stable and `spi_en` is asserted, the synchronized values are latched into the corresponding stable output registers.
  - On reset (`rst` high), all stable output registers are cleared to their default values.
