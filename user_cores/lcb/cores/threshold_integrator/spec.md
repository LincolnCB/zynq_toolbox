# Threshold Integrator Core

The `threshold_integrator` module is a safety core designed for the Rev D shim firmware. It captures the absolute values of DAC and ADC inputs/outputs and maintains a running average over a user-defined window. If the average exceeds a user-defined threshold, it sends a fault signal to the system.

## Inputs and Outputs

### Inputs:
- **Clock and Reset**:
  - `clk`: SPI clock signal for synchronous operation.
  - `rst`: Reset signal to initialize the module.

- **Control Signals**:
  - `enable`: Enable signal to start the integrator.
  - `sample_core_done`: Signal indicating that the DAC is ready.

- **Configuration Signals**:
  - `window`: 32-bit unsigned value defining the integration window size (range: \(2^{11}\) to \(2^{32} - 1\)).
  - `threshold_average`: 15-bit unsigned value defining the threshold average (absolute, range: 0 to \(2^{15} - 1\)).

- **Input Data**:
  - `value_in_concat`: 128-bit concatenated input containing 8 channels of 16-bit unsigned values (offset, zero at \(2^{15}\)).
  - `value_ready_concat`: 8-bit concatenated signal indicating data readiness for each channel.

### Outputs:
- **Status Signals**:
  - `over_threshold`: Signal indicating that the running average has exceeded the threshold.
  - `err_overflow`: Signal indicating a FIFO overflow error.
  - `err_underflow`: Signal indicating a FIFO underflow error.
  - `setup_done`: Signal indicating that the setup phase is complete.

## Operation

### States:
- **IDLE**: Waits for the `enable` signal to go high.
- **SETUP**: Performs intermediate calculations for chunk size, sub-average size, and sample size.
- **WAIT**: Waits for the `sample_core_done` signal before transitioning to the running state.
- **RUNNING**: Executes the main logic for inflow, outflow, and running sum calculations.
- **OUT_OF_BOUNDS**: Halts operation if the running sum exceeds the threshold.
- **ERROR**: Halts operation if a FIFO overflow or underflow occurs.

### Setup Phase:
1. Calculate `chunk_size`: Most significant bit (MSB) of the window minus 6 (max value: 25). This determines the granularity of the values stored in the internal FIFO, allowing for a wider window given the same depth FIFO. The chunk size is equal to the `sub_average_size` plus the `sample_size`.
2. Calculate `sub_average_size`: \( \max(0, \text{chunk_size} - 20) \) (max value: 5). Sub-averaging is used to reduce the number of samples processed directly by the FIFO when the window is larger than the maximum sample size would allow. It introduces slightly more error than the sample size, so is kept to a minimum.
3. Calculate `sample_size`: \( \min(20, \text{chunk_size}) \) (max value: 20). This defines the number of samples aggregated into a single FIFO entry.
4. Compute min/max values: \( \text{threshold_average} \times \text{window} \), converted to signed values.
5. Wait for `sample_core_done` to initialize timers and transition to the running state.

### Running Phase:
- **Inflow Logic**:
  - Per channel:
    - Capture the absolute value of the input when `value_ready` is high.
    - Add the inflow value to the running total sum and sub-average sum.
    - Reset and update timers for sub-averaging and sampling.
    - Push sample sums into the FIFO when the sample timer resets.
- **Outflow Logic**:
  - Pop 8 samples from the FIFO when the outflow timer reaches 16.
  - Subtract the average and remainder of the outflow sample from the running total sum.
- **Threshold Check**:
  - Transition to the `OUT_OF_BOUNDS` state if any running total sum exceeds the threshold.

### Sub-Averaging and Chunk Sizes:
Because each DAC/ADC sample is 8x16 bits, the window is 32 bits, and one FIFO block has a depth of 1024, we would be unable to store each individual sample in the FIFO. Instead, we use sample clustering and sub-averaging to reduce the number of samples stored in the FIFO. The total amount (in bits) we're recuding by (sample size plus sub-average size) is called the chunk size, and needs to be able to handle at least 25 bits.

We first utilize sample clustering. The FIFO has a width of 36 bits. Instead of storing each individual sample, we can store a number of individual DAC/ADC samples  summed into a single value. As such, the sample size can go up to 20 bits. Values are summed as they come in, and then pushed to the FIFO when \(2^{\text{sample_size}}\) of them have been summed. When the sample is popped from the FIFO, the average is calculated by dividing by \(2^{\text{sample_size}}\) (bit-shifting by `sample_size`). Each cycle, that average is subtracted from the running total sum. To handle the remainder of that division, we also subtract an additional 1 from the running total sum each cycle until the remainder is zero. The sample size is calculated so that the ultilized FIFO depth is maximized but not overused.

If the window is over 27 bits, however, we utilize sub-averaging to get our last 5 bits of data width. Here, instead of summing samples as they come in (for our sample size sums), we first sum them into a sub-average sum, then pass the sub-average of THAT into the sample clustering. Notably, this leaves the sub-average remainder behind, as the FIFO doesn't have room for that. This itroduces some error -- however, we keep the remainder as part of the sub-average sum, adding it to the next sub-averaging. This means the total error of the integrator due to this can't go over \(2^{5}\). We similarly calculate the sub-average size so that the FIFO depth is maximized but not overused, prioritizing the sample size before using sub-averaging.

### Error Handling:
- Transition to the `ERROR` state if a FIFO overflow or underflow occurs.

## Core Specifications

- **Clock Domain**: SPI clock.
- **FIFO**: One 36-bit wide FIFO with a depth of 1024.
- **Internal Signals**:
  - 48-bit signed min/max values.
  - 5-bit `chunk_size`, 3-bit `sub_average_size`, and 5-bit `sample_size`.
  - Timers for inflow sub-averaging, inflow sampling, and outflow sampling.
  - Per channel (8 channels):
    - 16-bit inflow absolute value.
    - 21-bit sub-average sum.
    - 36-bit inflow sample sum.
    - 36-bit queued FIFO in/out sample sums.
    - 16-bit outflow value and 20-bit outflow remainder.
    - 49-bit running total sum.
- **Reset Behavior**:
  - Zero all internal signals.
  - Reset the FIFO.
  - Transition to the `IDLE` state.
- **Trigger Behavior**:
  - Transition to the `RUNNING` state after setup and DAC readiness.

### Notes:
- The FIFO is used to manage the running sum efficiently, with a depth of 1024 and a width of 36 bits.
- Sample clustering and sub-averaging reduce the required FIFO depth while maintaining precision.
- The core ensures no drift by including remainders in subsequent calculations.
- The minimum window size is 2048 to ensure sufficient processing time for FIFO operations.

### References:
- [Xilinx Parameterized Macros](https://docs.amd.com/r/2024.1-English/ug953-vivado-7series-libraries/XPM_FIFO_SYNC)
- [7 Series Memory Resources](https://docs.amd.com/v/u/en-US/ug473_7Series_Memory_Resources)

