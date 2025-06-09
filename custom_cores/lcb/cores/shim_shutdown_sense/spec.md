# Hardware Shutdown Sense Core
*Updated 2025-06-04*

The `shim_shutdown_sense` module is responsible for monitoring the onboard shutdown mux and latching high if a shutdown is detected.

- **Inputs and Outputs**:
  - `clk`: Clock signal for synchronous operation.
  - `shutdown_sense_en`: Enable signal to activate the shutdown sense functionality.
  - `shutdown_sense_pin`: Input signal indicating a shutdown condition.
  - `shutdown_sense_sel`: 3-bit output that cycles through indices to select which bit of the `shutdown_sense` register to update.
  - `shutdown_sense`: 8-bit register that stores the latched shutdown states.

- **Operation**:
  - If `shutdown_sense_en` is low, the module initializes `shutdown_sense_sel` to `000` and clears the `shutdown_sense` register.
  - Otherwise, on each clock cycle, the `shutdown_sense_sel` value increments, cycling through all 8 bits of the `shutdown_sense` register.
  - If the `shutdown_sense_pin` is asserted (high), the corresponding bit in the `shutdown_sense` register, indexed by `shutdown_sense_sel`, is latched high to `1`.
