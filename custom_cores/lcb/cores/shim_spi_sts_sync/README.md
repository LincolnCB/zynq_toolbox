***Updated 2025-06-18***
# SPI System Status Synchronization Core

The `shim_spi_sts_sync` module synchronizes a variety of status signals from the SPI domain into the AXI (PS) clock domain, ensuring reliable and glitch-free transfer of asynchronous status information.

## Inputs and Outputs

### Inputs

- **Clocks and Reset**
  - `aclk`: AXI (PS) clock signal.
  - `aresetn`: Active-low reset signal for the AXI domain.

- **SPI Domain Status Inputs**
  - `spi_off`: Indicates the SPI subsystem is powered off.
  - `over_thresh [7:0]`: Integrator over-threshold status.
  - `thresh_underflow [7:0]`: Integrator threshold underflow status.
  - `thresh_overflow [7:0]`: Integrator threshold overflow status.
  - `bad_trig_cmd`: Bad trigger command detected.
  - `trig_data_buf_overflow`: Trigger data buffer overflow.
  - `dac_boot_fail [7:0]`: DAC boot failure status.
  - `bad_dac_cmd [7:0]`: Bad DAC command detected.
  - `dac_cal_oob [7:0]`: DAC calibration out-of-bounds.
  - `dac_val_oob [7:0]`: DAC value out-of-bounds.
  - `dac_cmd_buf_underflow [7:0]`: DAC command buffer underflow.
  - `unexp_dac_trig [7:0]`: Unexpected DAC trigger.
  - `adc_boot_fail [7:0]`: ADC boot failure status.
  - `bad_adc_cmd [7:0]`: Bad ADC command detected.
  - `adc_cmd_buf_underflow [7:0]`: ADC command buffer underflow.
  - `adc_data_buf_overflow [7:0]`: ADC data buffer overflow.
  - `unexp_adc_trig [7:0]`: Unexpected ADC trigger.

### Outputs

- **AXI Domain Synchronized Outputs**
  - `spi_off_stable`: Synchronized and stable SPI off status.
  - `over_thresh_stable [7:0]`: Synchronized and stable integrator over-threshold status.
  - `thresh_underflow_stable [7:0]`: Synchronized and stable integrator threshold underflow status.
  - `thresh_overflow_stable [7:0]`: Synchronized and stable integrator threshold overflow status.
  - `bad_trig_cmd_stable`: Synchronized and stable bad trigger command status.
  - `trig_data_buf_overflow_stable`: Synchronized and stable trigger data buffer overflow status.
  - `dac_boot_fail_stable [7:0]`: Synchronized and stable DAC boot failure status.
  - `bad_dac_cmd_stable [7:0]`: Synchronized and stable bad DAC command status.
  - `dac_cal_oob_stable [7:0]`: Synchronized and stable DAC calibration out-of-bounds status.
  - `dac_val_oob_stable [7:0]`: Synchronized and stable DAC value out-of-bounds status.
  - `dac_cmd_buf_underflow_stable [7:0]`: Synchronized and stable DAC command buffer underflow status.
  - `unexp_dac_trig_stable [7:0]`: Synchronized and stable unexpected DAC trigger status.
  - `adc_boot_fail_stable [7:0]`: Synchronized and stable ADC boot failure status.
  - `bad_adc_cmd_stable [7:0]`: Synchronized and stable bad ADC command status.
  - `adc_cmd_buf_underflow_stable [7:0]`: Synchronized and stable ADC command buffer underflow status.
  - `adc_data_buf_overflow_stable [7:0]`: Synchronized and stable ADC data buffer overflow status.
  - `unexp_adc_trig_stable [7:0]`: Synchronized and stable unexpected ADC trigger status.

## Operation

- Each input signal from the SPI domain is synchronized to the AXI clock domain using a 3-stage synchronizer with a stability check.
- For each signal, a stability flag is generated to indicate when the synchronized value is stable.
- When the stability flag is asserted, the synchronized value is latched into the corresponding stable output register.
- On AXI domain reset (`aresetn` low), all stable output registers are cleared to their default values (zeros).
