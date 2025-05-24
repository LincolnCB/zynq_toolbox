# Hardware Manager Core

The `hw_manager` module manages the hardware system's startup, operation, and shutdown processes. It implements a state machine to sequence power-up, configuration, SPI subsystem enable, and error/shutdown handling.

## Inputs and Outputs

### Inputs

- **Clock and Reset**
  - `clk`: Clock signal for synchronous operation.
  - `aresetn`: Active-low reset signal.

- **System Control**
  - `sys_en`: System enable signal to start the system.
  - `spi_off`: Indicates the SPI subsystem is powered off.
  - `ext_shutdown`: External shutdown signal.

- **Configuration Status**
  - `trig_lockout_oob`: Trigger lockout out of bounds.
  - `integ_thresh_avg_oob`: Integrator threshold average out of bounds.
  - `integ_window_oob`: Integrator window out of bounds.
  - `integ_en_oob`: Integrator enable register out of bounds.
  - `sys_en_oob`: System enable register out of bounds.
  - `lock_viol`: Configuration lock violation.

- **Shutdown Sense**
  - `shutdown_sense [7:0]`: Shutdown sense signals (per board).

- **DAC/ADC Thresholds**
  - `dac_over_thresh [7:0]`: DAC over-threshold (per board).
  - `adc_over_thresh [7:0]`: ADC over-threshold (per board).
  - `dac_thresh_underflow [7:0]`: DAC threshold FIFO underflow (per board).
  - `dac_thresh_overflow [7:0]`: DAC threshold FIFO overflow (per board).
  - `adc_thresh_underflow [7:0]`: ADC threshold FIFO underflow (per board).
  - `adc_thresh_overflow [7:0]`: ADC threshold FIFO overflow (per board).

- **DAC/ADC Buffers**
  - `dac_buf_underflow [7:0]`: DAC buffer underflow (per board).
  - `dac_buf_overflow [7:0]`: DAC buffer overflow (per board).
  - `adc_buf_underflow [7:0]`: ADC buffer underflow (per board).
  - `adc_buf_overflow [7:0]`: ADC buffer overflow (per board).

- **Premature Triggers**
  - `unexp_dac_trig [7:0]`: Unexpected DAC trigger (per board).
  - `unexp_adc_trig [7:0]`: Unexpected ADC trigger (per board).

### Outputs

- **System Control**
  - `unlock_cfg`: Unlock configuration registers (active high).
  - `spi_clk_power_n`: SPI clock power control (active low).
  - `spi_en`: SPI subsystem enable.
  - `shutdown_sense_en`: Enable shutdown sense logic.
  - `trig_en`: Trigger enable.
  - `n_shutdown_force`: Negated shutdown force signal.
  - `n_shutdown_rst`: Negated shutdown reset signal.

- **Status and Interrupts**
  - `status_word [31:0]`: Status word containing board number, status code, and state.
  - `ps_interrupt`: Interrupt signal to notify the processing system.

## Operation

### State Machine Overview

- **IDLE**: Waits for `sys_en` to go high. Checks for out-of-bounds configuration values. If any OOB condition is detected, transitions to HALTED with the corresponding status code and asserts `ps_interrupt`. If all checks pass, locks configuration and powers up the SPI clock.
- **CONFIRM_SPI_INIT**: Waits for the SPI subsystem to be powered off (`spi_off`). If not powered off within `SPI_INIT_WAIT`, transitions to HALTED with a timeout status.
- **RELEASE_SD_F**: Releases shutdown force (`n_shutdown_force` high) and waits for `SHUTDOWN_FORCE_DELAY`.
- **PULSE_SD_RST**: Pulses `n_shutdown_rst` low for `SHUTDOWN_RESET_PULSE`, then sets it high again.
- **SD_RST_DELAY**: Waits for `SHUTDOWN_RESET_DELAY` after pulsing shutdown reset, then enables shutdown sense, powers up SPI clock, and enables SPI.
- **START_SPI**: Waits for the SPI subsystem to start (`spi_running`). If not started within `SPI_START_WAIT`, transitions to HALTED with a timeout status. If started, enables triggers and asserts `ps_interrupt`.
- **RUNNING**: Normal operation. Continuously monitors for halt conditions. If any error or shutdown condition occurs, transitions to HALTED, disables outputs, and asserts `ps_interrupt`.
- **HALTED**: Waits for `sys_en` to go low, then returns to IDLE and clears status.

### Halt/Error Conditions

The system transitions to HALTED and sets the appropriate status code if any of the following occur:
- `sys_en` goes low (processing system shutdown)
- Configuration lock violation (`lock_viol`)
- Shutdown detected via `shutdown_sense` or `ext_shutdown`
- DAC/ADC thresholds exceeded or underflow/overflow conditions
- DAC/ADC buffers experience underflow or overflow
- Premature DAC/ADC triggers occur
- SPI subsystem fails to start within timeout

### Status Word Format

The 32-bit `status_word` is formatted as:
```
[31:29] - Board number (3 bits)
[28:4]  - Status code (25 bits)
[3:0]   - State machine state (4 bits)
```

### Status Codes

- `1`: STATUS_OK - System is operating normally.
- `2`: STATUS_PS_SHUTDOWN - Processing system shutdown.
- `3`: STATUS_TRIG_LOCKOUT_OOB - Trigger lockout out of bounds.
- `4`: STATUS_INTEG_THRESH_AVG_OOB - Integrator threshold average out of bounds.
- `5`: STATUS_INTEG_WINDOW_OOB - Integrator window out of bounds.
- `6`: STATUS_INTEG_EN_OOB - Integrator enable register out of bounds.
- `7`: STATUS_SYS_EN_OOB - System enable register out of bounds.
- `8`: STATUS_LOCK_VIOL - Configuration lock violation.
- `9`: STATUS_SHUTDOWN_SENSE - Shutdown sense detected.
- `10`: STATUS_EXT_SHUTDOWN - External shutdown triggered.
- `11`: STATUS_DAC_OVER_THRESH - DAC over threshold.
- `12`: STATUS_ADC_OVER_THRESH - ADC over threshold.
- `13`: STATUS_DAC_THRESH_UNDERFLOW - DAC threshold FIFO underflow.
- `14`: STATUS_DAC_THRESH_OVERFLOW - DAC threshold FIFO overflow.
- `15`: STATUS_ADC_THRESH_UNDERFLOW - ADC threshold FIFO underflow.
- `16`: STATUS_ADC_THRESH_OVERFLOW - ADC threshold FIFO overflow.
- `17`: STATUS_DAC_BUF_UNDERFLOW - DAC buffer underflow.
- `18`: STATUS_DAC_BUF_OVERFLOW - DAC buffer overflow.
- `19`: STATUS_ADC_BUF_UNDERFLOW - ADC buffer underflow.
- `20`: STATUS_ADC_BUF_OVERFLOW - ADC buffer overflow.
- `21`: STATUS_UNEXP_DAC_TRIG - Unexpected DAC trigger.
- `22`: STATUS_UNEXP_ADC_TRIG - Unexpected ADC trigger.
- `23`: STATUS_SPI_START_TIMEOUT - SPI start timeout.
- `24`: STATUS_SPI_INIT_TIMEOUT - SPI initialization timeout.

## Board Number Extraction

For error/status signals that are 8 bits wide (per board), the board number is extracted as the index of the first asserted bit.

---
This specification matches the implementation in `hw_manager.v` as of this revision.
