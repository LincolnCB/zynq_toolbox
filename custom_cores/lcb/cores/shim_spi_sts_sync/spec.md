# SPI System Status Synchronization Core

The `spi_sts_sync` module synchronizes status signals from the SPI clock domain to the AXI (PS) clock domain.

## Inputs and Outputs

### Inputs

- **Clocks and Reset**
  - `aclk`: AXI (PS) clock signal.
  - `spi_clk`: SPI clock signal.
  - `aresetn`: Active-low reset signal for the AXI domain.

- **SPI Domain Status Inputs**
  - `spi_off`: Indicates the SPI subsystem is powered off.
  - `over_thresh [7:0]`: DAC over-threshold status (per board).
  - `adc_over_thresh [7:0]`: ADC over-threshold status (per board).
  - `thresh_underflow [7:0]`: DAC threshold FIFO underflow status (per board).
  - `thresh_overflow [7:0]`: DAC threshold FIFO overflow status (per board).
  - `dac_buf_underflow [7:0]`: DAC buffer underflow status (per board).
  - `adc_buf_overflow [7:0]`: ADC buffer overflow status (per board).
  - `unexp_dac_trig [7:0]`: Unexpected DAC trigger status (per board).
  - `unexp_adc_trig [7:0]`: Unexpected ADC trigger status (per board).

### Outputs

- **AXI Domain Synchronized Outputs**
  - `spi_off_stable`: Synchronized and stable SPI off status.
  - `over_thresh_stable [7:0]`: Synchronized and stable DAC over-threshold status.
  - `adc_over_thresh_stable [7:0]`: Synchronized and stable ADC over-threshold status.
  - `thresh_underflow_stable [7:0]`: Synchronized and stable DAC threshold underflow status.
  - `thresh_overflow_stable [7:0]`: Synchronized and stable DAC threshold overflow status.
  - `dac_buf_underflow_stable [7:0]`: Synchronized and stable DAC buffer underflow status.
  - `adc_buf_overflow_stable [7:0]`: Synchronized and stable ADC buffer overflow status.
  - `unexp_dac_trig_stable [7:0]`: Synchronized and stable unexpected DAC trigger status.
  - `unexp_adc_trig_stable [7:0]`: Synchronized and stable unexpected ADC trigger status.

## Operation

- Each input signal from the SPI domain is synchronized to the AXI clock domain using a 3-stage synchronizer with a stability check.
- For each signal, a stability flag is generated to indicate when the synchronized value is stable.
- When the stability flag is asserted, the synchronized value is latched into the corresponding stable output register.
- On AXI domain reset (`aresetn` low), all stable output registers are cleared to their default values (zeros).

