***Updated 2025-08-08***
# Hardware Manager Core

The `shim_hw_manager` module manages the hardware system's startup, operation, and shutdown processes. It implements a state machine to sequence power-up, configuration, SPI subsystem enable, and error/shutdown handling.

## Inputs and Outputs

### Inputs

- **Clock and Reset**
  - `clk`: System clock.
  - `aresetn`: Active-low reset.

- **System Control**
  - `sys_en`: System enable (turn the system on).
  - `spi_off`: SPI system powered off.
  - `ext_shutdown`: External shutdown.

- **Configuration Status**
  - `lock_viol`: Configuration lock violation.
  - `sys_en_oob`: System enable register out of bounds.
  - `buffer_reset_oob`: Buffer reset out of bounds.
  - `integ_thresh_avg_oob`: Integrator threshold average out of bounds.
  - `integ_window_oob`: Integrator window out of bounds.
  - `integ_en_oob`: Integrator enable register out of bounds.
  - `boot_test_skip_oob`: Boot test skip out of bounds.

- **Shutdown Sense**
  - `shutdown_sense [7:0]`: Shutdown sense (per board).

- **Integrator Status**
  - `over_thresh [7:0]`: DAC over threshold (per board).
  - `thresh_underflow [7:0]`: DAC threshold core FIFO underflow (per board).
  - `thresh_overflow [7:0]`: DAC threshold core FIFO overflow (per board).

- **Trigger Buffer and Commands**
  - `bad_trig_cmd`: Bad trigger command.
  - `trig_cmd_buf_overflow`: Trigger command buffer overflow.
  - `trig_data_buf_underflow`: Trigger data buffer underflow.
  - `trig_data_buf_overflow`: Trigger data buffer overflow.

- **DAC Buffers and Commands**
  - `dac_boot_fail [7:0]`: DAC boot failure (per board).
  - `bad_dac_cmd [7:0]`: Bad DAC command (per board).
  - `dac_cal_oob [7:0]`: DAC calibration out of bounds (per board).
  - `dac_val_oob [7:0]`: DAC value out of bounds (per board).
  - `dac_cmd_buf_underflow [7:0]`: DAC command buffer underflow (per board).
  - `dac_cmd_buf_overflow [7:0]`: DAC command buffer overflow (per board).
  - `unexp_dac_trig [7:0]`: Unexpected DAC trigger (per board).

- **ADC Buffers and Commands**
  - `adc_boot_fail [7:0]`: ADC boot failure (per board).
  - `bad_adc_cmd [7:0]`: Bad ADC command (per board).
  - `adc_cmd_buf_underflow [7:0]`: ADC command buffer underflow (per board).
  - `adc_cmd_buf_overflow [7:0]`: ADC command buffer overflow (per board).
  - `adc_data_buf_underflow [7:0]`: ADC data buffer underflow (per board).
  - `adc_data_buf_overflow [7:0]`: ADC data buffer overflow (per board).
  - `unexp_adc_trig [7:0]`: Unexpected ADC trigger (per board).

### Outputs

- **System Control**
  - `unlock_cfg`: Lock configuration.
  - `spi_clk_gate`: SPI clock gate.
  - `spi_en`: SPI subsystem enable.
  - `shutdown_sense_en`: Shutdown sense enable.
  - `block_buffers`: Block command/data buffers (active high).
  - `n_shutdown_force`: Shutdown force (negated).
  - `n_shutdown_rst`: Shutdown reset (negated).

- **Status and Interrupts**
  - `status_word [31:0]`: Status word containing board number, status code, and state.
  - `ps_interrupt`: Interrupt signal.

## Operation

### State Machine Overview

The state machine states are encoded as follows:
- `4'd1`: `S_IDLE` - Waits for `sys_en` to go high. Checks for out-of-bounds configuration values (`sys_en_oob`, `buffer_reset_oob`, `integ_thresh_avg_oob`, `integ_window_oob`, `integ_en_oob`, `boot_test_skip_oob`). If any OOB condition is detected, transitions to `S_HALTING` with the corresponding status code and asserts `ps_interrupt`. If all checks pass, locks configuration and powers up the SPI clock.
- `4'd2`: `S_CONFIRM_SPI_RST` - Makes sure the SPI system is powered off (`spi_off`). If not powered off within `SPI_RESET_WAIT`, transitions to `S_HALTING` with a timeout status.
- `4'd3`: `S_POWER_ON_CRTL_BRD` - Releases shutdown force (`n_shutdown_force` high) and waits for `SHUTDOWN_FORCE_DELAY`.
- `4'd4`: `S_CONFIRM_SPI_START` - Enables shutdown sense, SPI clock, and SPI subsystem, then waits for the SPI subsystem to start (`spi_off` deasserted). If not started within `SPI_START_WAIT` or if any DAC/ADC boot failure occurs, transitions to `S_HALTING` with the appropriate status code.
- `4'd5`: `S_POWER_ON_AMP_BRD` - Pulses `n_shutdown_rst` low for `SHUTDOWN_RESET_PULSE`, then sets it high again.
- `4'd6`: `S_AMP_POWER_WAIT` - Waits for `SHUTDOWN_RESET_DELAY` after pulsing shutdown reset, then unblocks command/data buffers and asserts `ps_interrupt`.
- `4'd7`: `S_RUNNING` - Normal operation. Continuously monitors for halt conditions. If any error or shutdown condition occurs, transitions to `S_HALTING`, disables outputs, and asserts `ps_interrupt`.
- `4'd8`: `S_HALTING` - Prepares to halt the system. Takes one cycle to set all signals to the initial state and assert `ps_interrupt`.
- `4'd9`: `S_HALTED` - Halted state. All outputs are disabled, and the system waits for a reset or `sys_en` to go low.

### Halt/Error Conditions

The system transitions through `S_HALTING` to `S_HALTED` and sets the appropriate status code if any of the following occur:
- `sys_en` goes low (processing system shutdown)
- Configuration lock violation (`lock_viol`)
- Out-of-bounds configuration values (`sys_en_oob`, `buffer_reset_oob`, `integ_thresh_avg_oob`, `integ_window_oob`, `integ_en_oob`, `boot_test_skip_oob`)
- Shutdown detected via `shutdown_sense` or `ext_shutdown`
- Integrator thresholds exceeded or hardware error underflow/overflow conditions
- Trigger buffer or command errors
- DAC/ADC boot failure, buffer or command errors (per board)
- Unexpected DAC/ADC triggers occur
- SPI subsystem fails to start or initialize within timeout

### Status Word Format

The 32-bit `status_word` is formatted as:
```
[31:29] - Board number (3 bits)
[28:4]  - Status code (25 bits)
[3:0]   - State machine state (4 bits)
```

### Status Codes

Status codes are 25 bits wide and include:

- `25'h0001`: `STS_OK` - System is operating normally.
- `25'h0002`: `STS_PS_SHUTDOWN` - Processing system shutdown.
- `25'h0100`: `STS_SPI_RESET_TIMEOUT` - SPI initialization timeout.
- `25'h0101`: `STS_SPI_START_TIMEOUT` - SPI start timeout.
- `25'h0200`: `STS_LOCK_VIOL` - Configuration lock violation.
- `25'h0201`: `STS_SYS_EN_OOB` - System enable register out of bounds.
- `25'h0202`: `STS_BUFFER_RESET_OOB` - Buffer reset out of bounds.
- `25'h0203`: `STS_INTEG_THRESH_AVG_OOB` - Integrator threshold average out of bounds.
- `25'h0204`: `STS_INTEG_WINDOW_OOB` - Integrator window out of bounds.
- `25'h0205`: `STS_INTEG_EN_OOB` - Integrator enable register out of bounds.
- `25'h0206`: `STS_BOOT_TEST_SKIP_OOB` - Boot test skip out of bounds.
- `25'h0300`: `STS_SHUTDOWN_SENSE` - Shutdown sense detected.
- `25'h0301`: `STS_EXT_SHUTDOWN` - External shutdown triggered.
- `25'h0400`: `STS_OVER_THRESH` - DAC over threshold.
- `25'h0401`: `STS_THRESH_UNDERFLOW` - DAC threshold FIFO underflow.
- `25'h0402`: `STS_THRESH_OVERFLOW` - DAC threshold FIFO overflow.
- `25'h0500`: `STS_BAD_TRIG_CMD` - Bad trigger command.
- `25'h0501`: `STS_TRIG_CMD_BUF_OVERFLOW` - Trigger command buffer overflow.
- `25'h0502`: `STS_TRIG_DATA_BUF_UNDERFLOW` - Trigger data buffer underflow.
- `25'h0503`: `STS_TRIG_DATA_BUF_OVERFLOW` - Trigger data buffer overflow.
- `25'h0600`: `STS_DAC_BOOT_FAIL` - DAC boot failure.
- `25'h0601`: `STS_BAD_DAC_CMD` - Bad DAC command.
- `25'h0602`: `STS_DAC_CAL_OOB` - DAC calibration out of bounds.
- `25'h0603`: `STS_DAC_VAL_OOB` - DAC value out of bounds.
- `25'h0604`: `STS_DAC_BUF_UNDERFLOW` - DAC command buffer underflow.
- `25'h0605`: `STS_DAC_BUF_OVERFLOW` - DAC command buffer overflow.
- `25'h0606`: `STS_UNEXP_DAC_TRIG` - Unexpected DAC trigger.
- `25'h0700`: `STS_ADC_BOOT_FAIL` - ADC boot failure.
- `25'h0701`: `STS_BAD_ADC_CMD` - Bad ADC command.
- `25'h0702`: `STS_ADC_CMD_BUF_UNDERFLOW` - ADC command buffer underflow.
- `25'h0703`: `STS_ADC_CMD_BUF_OVERFLOW` - ADC command buffer overflow.
- `25'h0704`: `STS_ADC_DATA_BUF_UNDERFLOW` - ADC data buffer underflow.
- `25'h0705`: `STS_ADC_DATA_BUF_OVERFLOW` - ADC data buffer overflow.
- `25'h0706`: `STS_UNEXP_ADC_TRIG` - Unexpected ADC trigger.

## Board Number Extraction

For error/status signals that are 8 bits wide (per board), the board number is extracted as the index of the first asserted bit (0–7).
