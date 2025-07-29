***Updated 2025-06-04***
# AXI Shim Config Core

The `shim_axi_sys_ctrl` module provides a configurable interface for managing system parameters and operation via an AXI4-Lite interface.

- **Inputs and Outputs**:
  - **Inputs**:
    - `aclk`: AXI clock signal.
    - `aresetn`: Active-low reset signal.
    - `unlock`: Signal to unlock the configuration registers.
    - `s_axi_awaddr`: AXI4-Lite write address.
    - `s_axi_awvalid`: AXI4-Lite write address valid.
    - `s_axi_wdata`: AXI4-Lite write data.
    - `s_axi_wstrb`: AXI4-Lite write strobe.
    - `s_axi_wvalid`: AXI4-Lite write data valid.
    - `s_axi_bready`: AXI4-Lite write response ready.
    - `s_axi_araddr`: AXI4-Lite read address.
    - `s_axi_arvalid`: AXI4-Lite read address valid.
    - `s_axi_rready`: AXI4-Lite read response ready.
  - **Outputs**:
    - `integ_thresh_avg`: 15-bit integration threshold average configuration.
    - `integ_window`: 32-bit integration window configuration.
    - `integ_en`: Integration enable signal.
    - `buffer_reset`: 25-bit buffer reset configuration.
    - `sys_en`: System enable signal.
    - `integ_thresh_avg_oob`: Out-of-bounds signal for integration threshold average.
    - `integ_window_oob`: Out-of-bounds signal for integration window.
    - `integ_en_oob`: Out-of-bounds signal for integration enable.
    - `sys_en_oob`: Out-of-bounds signal for system enable.
    - `lock_viol`: Signal indicating a lock violation.
    - `s_axi_awready`: AXI4-Lite write address ready.
    - `s_axi_wready`: AXI4-Lite write data ready.
    - `s_axi_bresp`: AXI4-Lite write response.
    - `s_axi_bvalid`: AXI4-Lite write response valid.
    - `s_axi_arready`: AXI4-Lite read address ready.
    - `s_axi_rdata`: AXI4-Lite read data.
    - `s_axi_rresp`: AXI4-Lite read response.
    - `s_axi_rvalid`: AXI4-Lite read data valid.

- **Operation**:
  - On reset (`aresetn` low), all internal and output configuration values are initialized to their parameterized default values, capped to their valid ranges.
  - Output configuration values are updated to the AXI-written internal variables and locked when the `sys_en` bit is set high by the AXI interface. Once locked, any attempt to modify the values results in a lock violation, indicated by latching high the `lock_viol` signal.
  - Each internal configuration value is checked against a parameterized range defined in local parameters. If a value is outside its valid range, a corresponding "out-of-bounds" signal is asserted.
  - The `buffer_reset` signal is unique in that it is not locked by the `sys_en` signal. While reset is active, it is set to `25b1`, but it defaults to `25b0`.
  - The `unlock` signal can be used to clear the lock and allow modifications to the configuration registers if `sys_en` has been set low.
  - The module supports AXI4-Lite read and write operations for accessing and modifying configuration values. Write responses include error codes to indicate out-of-bounds violations or lock violations.

