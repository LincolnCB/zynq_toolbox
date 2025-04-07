# Hardware Manager Core

The `hw_manager` module is responsible for managing the hardware system's startup, operation, and shutdown processes. It operates as follows:

## Inputs and Outputs

### Inputs:
- **Clock and Reset**:
	- `clk`: Clock signal for synchronous operation.
	- `rst`: Reset signal to initialize the module.

- **System Control**:
	- `sys_en`: System enable signal to start the system.
	- `ext_shutdown`: External shutdown signal.

- **Configuration Signals**:
	- `trig_lockout_oob`: Trigger lockout out of bounds.
	- `cal_offset_oob`: Calibration offset out of bounds.
	- `dac_divider_oob`: DAC divider out of bounds.
	- `integ_thresh_avg_oob`: Integrator threshold average out of bounds.
	- `integ_window_oob`: Integrator window out of bounds.
	- `integ_en_oob`: Integrator enable register out of bounds.
	- `sys_en_oob`: System enable register out of bounds.
	- `lock_viol`: Configuration lock violation.

- **Shutdown Sense**:
	- `shutdown_sense`: 8-bit input signal indicating shutdown conditions per board.

- **DAC/ADC Thresholds**:
	- `dac_over_thresh`: 8-bit signal indicating DAC over-threshold conditions per board.
	- `adc_over_thresh`: 8-bit signal indicating ADC over-threshold conditions per board.
	- `dac_thresh_underflow`: 8-bit signal indicating DAC threshold FIFO underflow per board.
	- `dac_thresh_overflow`: 8-bit signal indicating DAC threshold FIFO overflow per board.
	- `adc_thresh_underflow`: 8-bit signal indicating ADC threshold FIFO underflow per board.
	- `adc_thresh_overflow`: 8-bit signal indicating ADC threshold FIFO overflow per board.

- **DAC/ADC Buffers**:
	- `dac_buf_underflow`: 8-bit signal indicating DAC buffer underflow per board.
	- `dac_buf_overflow`: 8-bit signal indicating DAC buffer overflow per board.
	- `adc_buf_underflow`: 8-bit signal indicating ADC buffer underflow per board.
	- `adc_buf_overflow`: 8-bit signal indicating ADC buffer overflow per board.

- **Premature Triggers**:
	- `premat_dac_trig`: 8-bit signal indicating premature DAC trigger per board.
	- `premat_adc_trig`: 8-bit signal indicating premature ADC trigger per board.
	- `premat_dac_div`: 8-bit signal indicating premature DAC division per board.
	- `premat_adc_div`: 8-bit signal indicating premature ADC division per board.

- **Subsystem Status**:
	- `dac_buf_loaded`: Indicates that the DAC buffer is preloaded.
	- `spi_running`: Indicates that the SPI subsystem is operational.

### Outputs:
- **System Control**:
	- `sys_rst`: System reset signal.
	- `unlock_cfg`: Configuration lock control signal.
	- `dma_en`: DMA enable signal.
	- `spi_en`: SPI subsystem enable signal.
	- `trig_en`: Trigger enable signal.

- **Shutdown Control**:
	- `n_shutdown_force`: Negated shutdown force signal.
	- `n_shutdown_rst`: Negated shutdown reset signal.

- **Status and Interrupts**:
	- `status_word`: 32-bit status word containing the board number, status code, and state.
	- `ps_interrupt`: Interrupt signal to notify the processing system.

## Operation

### Startup Sequence:
1. **Idle State**:
	 - Waits for `sys_en` to go high.
	 - Checks for out-of-bounds (OOB) configuration values when `sys_en` is asserted. If any OOB condition is detected, the system halts and sets the corresponding status code.

2. **Release Shutdown Force**:
	 - Sets `n_shutdown_force` high.
	 - Waits for a delay (`SHUTDOWN_FORCE_DELAY`) to stabilize the DAC/ADC before starting the power stage.

3. **Pulse Shutdown Reset**:
	 - Pulses `n_shutdown_rst` low for a short duration (`SHUTDOWN_RESET_PULSE`).
	 - Sets `n_shutdown_rst` high again after the pulse.

4. **Shutdown Reset Delay**:
	 - Waits for a delay (`SHUTDOWN_RESET_DELAY`) to allow the power stage to boot.

5. **Enable DMA**:
	 - Enables DMA transfer via `dma_en`.
	 - Waits for `dac_buf_loaded` to confirm the buffer is preloaded.
	 - Halts if the buffer is not loaded within the timeout (`BUF_LOAD_WAIT`).

6. **Enable SPI**:
	 - Enables the SPI subsystem via `spi_en`.
	 - Waits for `spi_running` to confirm the SPI subsystem is operational.
	 - Halts if the SPI subsystem does not start within the timeout (`SPI_START_WAIT`).

7. **Running State**:
	 - Enables triggers via `trig_en`.
	 - Continuously monitors for errors or shutdown conditions.

### Halt Conditions:
- `sys_en` goes low.
- Configuration lock violation (`lock_viol`).
- Shutdown detected via `shutdown_sense` or `ext_shutdown`.
- DAC/ADC thresholds exceeded or underflow/overflow conditions occur.
- DAC/ADC buffers experience underflow or overflow.
- Premature DAC/ADC triggers or divisions occur.

### Status Word:
- The 32-bit `status_word` is formatted as follows:
	```
	[31:29] - Board number (3 bits)
	[28:4]  - Status code (25 bits)
	[3:0]   - State machine state (4 bits)
	```

### Status Codes:
- `1`: STATUS_OK - System is operating normally.
- `2`: STATUS_PS_SHUTDOWN - Processing system shutdown.
- `3`: STATUS_TRIG_LOCKOUT_OOB - Trigger lockout out of bounds.
- `4`: STATUS_CAL_OFFSET_OOB - Calibration offset out of bounds.
- `5`: STATUS_DAC_DIVIDER_OOB - DAC divider out of bounds.
- `6`: STATUS_INTEG_THRESH_AVG_OOB - Integrator threshold average out of bounds.
- `7`: STATUS_INTEG_WINDOW_OOB - Integrator window out of bounds.
- `8`: STATUS_INTEG_EN_OOB - Integrator enable register out of bounds.
- `9`: STATUS_SYS_EN_OOB - System enable register out of bounds.
- `10`: STATUS_LOCK_VIOL - Configuration lock violation.
- `11`: STATUS_SHUTDOWN_SENSE - Shutdown sense detected.
- `12`: STATUS_EXT_SHUTDOWN - External shutdown triggered.
- `13`: STATUS_DAC_OVER_THRESH - DAC over threshold.
- `14`: STATUS_ADC_OVER_THRESH - ADC over threshold.
- `15`: STATUS_DAC_THRESH_UNDERFLOW - DAC threshold FIFO underflow.
- `16`: STATUS_DAC_THRESH_OVERFLOW - DAC threshold FIFO overflow.
- `17`: STATUS_ADC_THRESH_UNDERFLOW - ADC threshold FIFO underflow.
- `18`: STATUS_ADC_THRESH_OVERFLOW - ADC threshold FIFO overflow.
- `19`: STATUS_DAC_BUF_UNDERFLOW - DAC buffer underflow.
- `20`: STATUS_DAC_BUF_OVERFLOW - DAC buffer overflow.
- `21`: STATUS_ADC_BUF_UNDERFLOW - ADC buffer underflow.
- `22`: STATUS_ADC_BUF_OVERFLOW - ADC buffer overflow.
- `23`: STATUS_PREMAT_DAC_TRIG - Premature DAC trigger.
- `24`: STATUS_PREMAT_ADC_TRIG - Premature ADC trigger.
- `25`: STATUS_PREMAT_DAC_DIV - Premature DAC division.
- `26`: STATUS_PREMAT_ADC_DIV - Premature ADC division.
- `27`: STATUS_DAC_BUF_FILL_TIMEOUT - DAC buffer fill timeout.
- `28`: STATUS_SPI_START_TIMEOUT - SPI start timeout.
