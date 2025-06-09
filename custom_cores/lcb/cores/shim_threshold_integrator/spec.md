# Threshold Integrator Core
*Updated 2025-06-04*

The `shim_threshold_integrator` module is a safety core designed for the Rev D shim firmware. It captures the absolute values of DAC and ADC inputs/outputs and maintains a running sum over a user-defined window. If any channel's sum exceeds a user-defined threshold, it sends a fault signal to the system.

## Inputs and Outputs

### Inputs:
- **Clock and Reset**:
  - `clk`: Clock signal for synchronous operation.
  - `resetn`: Active-low reset signal to initialize the module.

- **Control Signals**:
  - `enable`: Enable signal to start the integrator.
  - `sample_core_done`: Signal indicating that the DAC/ADC core is ready.

- **Configuration Signals**:
  - `window`: 32-bit unsigned value defining the integration window size (range: \(2^{11}\) to \(2^{32} - 1\)).
  - `threshold_average`: 15-bit unsigned value defining the threshold average (absolute, range: 0 to \(2^{15} - 1\)).

- **Input Data**:
  - `abs_sample_concat`: 120-bit concatenated input containing 8 channels of 15-bit unsigned absolute values.

### Outputs:
- **Status Signals**:
  - `over_thresh`: Signal indicating that the running sum has exceeded the threshold.
  - `err_overflow`: Signal indicating a FIFO overflow error.
  - `err_underflow`: Signal indicating a FIFO underflow error.
  - `setup_done`: Signal indicating that the setup phase is complete.

## Operation

### States:
- **IDLE**: Waits for the `enable` signal to go high. Calculates the sample size based on the window size.
- **SETUP**: Performs shift-add multiplication to compute the maximum allowed value (`max_value = threshold_average * (window >> 4)`). Sets up the sample mask and transitions to WAIT.
- **WAIT**: Waits for the `sample_core_done` signal before initializing timers and transitioning to the RUNNING state.
- **RUNNING**: Executes the main logic for inflow, outflow, and running sum calculations. Monitors for threshold violations and FIFO errors.
- **OUT_OF_BOUNDS**: Halts operation if the running sum exceeds the threshold.
- **ERROR**: Halts operation if a FIFO overflow or underflow occurs.

### Setup Phase:
1. **Sample Size Calculation**: Determines the number of samples to aggregate into a single FIFO entry based on the most significant bit of the window.
2. **Max Value Calculation**: Uses shift-add multiplication to compute `max_value = threshold_average * (window >> 4)`.
3. **Sample Mask**: Sets the mask for the sample size.
4. **Wait for Core Ready**: Waits for `sample_core_done` to initialize timers and transition to the running state.

### Running Phase:
- **Inflow Logic**:
  - For each channel, captures the absolute value of the input every 16th clock cycle.
  - Aggregates values into a sample sum.
  - Pushes sample sums into the FIFO when the inflow sample timer resets.
- **Outflow Logic**:
  - Pops 8 samples from the FIFO when the outflow timer reaches 16.
  - Moves queued samples into outflow values and remainders.
  - Updates the running total sum for each channel using the difference between inflow and outflow values.
- **Threshold Check**:
  - If any running total sum exceeds the threshold, transitions to the `OUT_OF_BOUNDS` state.

### Error Handling:
- If a FIFO overflow or underflow occurs, transitions to the `ERROR` state and asserts the corresponding error signal.

## Core Specifications

- **Clock Domain**: System clock.
- **FIFO**: One 36-bit wide FIFO with a depth of 1024.
- **Internal Signals**:
  - 44-bit unsigned `max_value`.
  - 5-bit `sample_size` and 25-bit `sample_mask`.
  - Timers for inflow sampling and outflow sampling.
  - Per channel (8 channels):
    - 15-bit inflow absolute value.
    - 36-bit inflow sample sum.
    - 36-bit queued FIFO in/out sample sums.
    - 15/16-bit outflow value and 20-bit outflow remainder.
    - 45-bit running total sum.
- **Reset Behavior**:
  - All internal signals and outputs are cleared.
  - FIFO is reset.
  - State machine returns to `IDLE`.

### Notes:
- The FIFO is used to manage the running sum efficiently, with a depth of 1024 and a width of 36 bits.
- Sample clustering reduces the required FIFO depth while maintaining precision.
- The core ensures no drift by including remainders in subsequent calculations.
- The minimum window size is 2048 to ensure sufficient processing time for FIFO operations.

### References:
- [7 Series Memory Resources](https://docs.amd.com/v/u/en-US/ug473_7Series_Memory_Resources)
