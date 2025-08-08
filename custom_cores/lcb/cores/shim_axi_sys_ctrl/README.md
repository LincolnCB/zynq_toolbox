***Updated 2025-06-04***
# AXI Shim Config Core

The `shim_axi_sys_ctrl` module provides a configurable interface for managing system parameters and operation via an AXI4-Lite interface.

## Register Map
| Address Offset | 32-bit Offset | Register                | Width   | Description                                   | Default Value         | Range/Notes                  |
|:--------------:|:-------------:|:-----------------------|:--------|:----------------------------------------------|:----------------------|:-----------------------------|
| 0x00           | 0             | `sys_en`               | 1 bit   | System enable (locks configuration)            | 0                     | 0 or 1                       |
| 0x04           | 1             | `buffer_reset`         | 26 bits | Buffer reset                                  | 0                     | Not locked by `sys_en`       |
| 0x08           | 2             | `integ_thresh_avg`     | 15 bits | Integration threshold average                  | 16384                 | 1 to 32767                   |
| 0x0C           | 3             | `integ_window`         | 32 bits | Integration window                            | 5000000               | 2048 to 0xFFFFFFFF           |
| 0x10           | 4             | `integ_en`             | 1 bit   | Integration enable                            | 1                     | 0 or 1                       |
| 0x14           | 5             | `boot_test_skip`       | 16 bits | Boot test skip mask (per-core)                | 0                     | 0 to 0xFFFF                  |

- **Inputs**:
  - `aclk`: AXI clock signal.
  - `aresetn`: Active-low reset signal.
  - `unlock`: Signal to unlock the configuration registers.
  - AXI4-Lite signals: `s_axi_awaddr`, `s_axi_awvalid`, `s_axi_wdata`, `s_axi_wstrb`, `s_axi_wvalid`, `s_axi_bready`, `s_axi_araddr`, `s_axi_arvalid`, `s_axi_rready`.

- **Outputs**:
  - `sys_en`: System enable signal.
  - `buffer_reset`: 26-bit buffer reset configuration.
  - `integ_thresh_avg`: 15-bit integration threshold average configuration.
  - `integ_window`: 32-bit integration window configuration.
  - `integ_en`: Integration enable signal.
  - `boot_test_skip`: 16-bit boot test skip mask.
  - Out-of-bounds signals: `sys_en_oob`, `buffer_reset_oob`, `integ_thresh_avg_oob`, `integ_window_oob`, `integ_en_oob`, `boot_test_skip_oob`.
  - `lock_viol`: Signal indicating a lock violation.
  - AXI4-Lite signals: `s_axi_awready`, `s_axi_wready`, `s_axi_bresp`, `s_axi_bvalid`, `s_axi_arready`, `s_axi_rdata`, `s_axi_rresp`, `s_axi_rvalid`.

## Operation

- On reset (`aresetn` low), all internal and output configuration values are initialized to their parameterized default values, capped to their valid ranges.
- Output configuration values are updated to the AXI-written internal variables and locked when the `sys_en` bit is set high by the AXI interface. Once locked, any attempt to modify the values results in a lock violation, indicated by latching high the `lock_viol` signal.
- Each internal configuration value is checked against a parameterized range defined in local parameters. If a value is outside its valid range, a corresponding "out-of-bounds" signal is asserted.
- The `buffer_reset` signal is unique in that it is not locked by the `sys_en` signal. While reset is active, it is set to `26'b1`, but it defaults to `26'b0`.
- The `boot_test_skip` register allows skipping boot tests for selected cores, with each bit corresponding to a core.
- The `unlock` signal can be used to clear the lock and allow modifications to the configuration registers if `sys_en` has been set low.
- The module supports AXI4-Lite read and write operations for accessing and modifying configuration values. Write responses include error codes to indicate out-of-bounds violations or lock violations.

