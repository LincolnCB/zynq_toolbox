# Hardware Shutdown Sense Core
The `shutdown_sense` module is responsible for monitoring a shutdown signal and recording its state. It operates as follows:

- **Inputs and Outputs**:
  - `clk`: Clock signal for synchronous operation.
  - `rst`: Reset signal to initialize the module.
  - `shutdown_sense_pin`: Input signal indicating a shutdown condition.
  - `shutdown_sense_sel`: 3-bit output that cycles through indices to select which bit of the `shutdown_sense` register to update.
  - `shutdown_sense`: 8-bit register that stores the latched shutdown states.

- **Operation**:
  - On reset (`rst` high), the module initializes `shutdown_sense_sel` to `000` and clears the `shutdown_sense` register.
  - On each clock cycle, the `shutdown_sense_sel` value increments, cycling through all 8 bits of the `shutdown_sense` register.
  - If the `shutdown_sense_pin` is asserted (high), the corresponding bit in the `shutdown_sense` register, indexed by `shutdown_sense_sel`, is set to `1`.

This module provides a mechanism to sequentially monitor and record the state of the shutdown signal across multiple cycles.
