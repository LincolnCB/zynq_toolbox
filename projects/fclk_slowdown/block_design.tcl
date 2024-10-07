## Instantiate the processing system and connect it to fixed IO and DDR

# Create the PS (processing_system7)
# - GP AXI 0 (Master) clock is connected to the processing system's first clock, FCLK_CLK0
cell xilinx.com:ip:processing_system7:5.5 ps_0 {
  PCW_FPGA0_PERIPHERAL_FREQMHZ 5.0
} {
  M_AXI_GP0_ACLK ps_0/FCLK_CLK0
}

# Create all required interconnections
# - Make the processing system's FIXED_IO and DDR interfaces external
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {
  make_external {FIXED_IO, DDR}
  Master Disable
  Slave Disable
} [get_bd_cells ps_0]

## Connect the FLCK externally
