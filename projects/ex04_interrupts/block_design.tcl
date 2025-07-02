# No external FPGA ports are used in this project.

## Instantiate the processing system

# Create the PS (processing_system7)
# Config:
# - Unused AXI ACP port disabled (or it will complain that the port's clock is not connected)
# Connections:
# - GP AXI 0 (Master) clock is connected to the processing system's first clock, FCLK_CLK0
init_ps ps {
  PCW_USE_S_AXI_ACP 0
} {
  M_AXI_GP0_ACLK ps/FCLK_CLK0
}

## Create the reset manager
# Create proc_sys_reset
# - Resetn is constant low (active high)
cell xilinx.com:ip:proc_sys_reset rst_0 {} {
  ext_reset_in ps/FCLK_RESET0_N
  slowest_sync_clk ps/FCLK_CLK0
}
