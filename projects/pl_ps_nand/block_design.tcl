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


## Create the reset hub

# Create xlconstant to hold reset low
cell xilinx.com:ip:xlconstant const_0

# Create proc_sys_reset
# - Reset is constant low (active high)
cell xilinx.com:ip:proc_sys_reset rst_0 {} {
  ext_reset_in const_0/dout
  slowest_sync_clk ps_0/FCLK_CLK0
}

## Create axi hub, where we use CFG as the inputs and STS as the outputs

# Create axi_hub
# - Config width is 16 bits, first 8 are NANDed with last 8
# - Status width is 8 bits, output of NAND
# - Connect the axi_hub to the processing system's GP AXI 0 interface
# - Connect the axi_hub to the processing system's clock and the reset hub
cell pavel-demin:user:axi_hub hub_0 {
  CFG_DATA_WIDTH 16
  STS_DATA_WIDTH 8
} {
  S_AXI ps_0/M_AXI_GP0
  aclk ps_0/FCLK_CLK0
  aresetn rst_0/peripheral_aresetn
}

# Assign the address of the axi_hub in the PS address space
assign_bd_address -target_address_space /ps_0/Data [get_bd_addr_segs hub_0/s_axi/reg0] -force

## Do a NAND on the CFG bits and output to STS

# Slice the CFG bits to get the first 8 bits
cell pavel-demin:user:port_slicer cfg_slice_0 {
  DIN_WIDTH 16 DIN_FROM 7 DIN_TO 0
} {
  din hub_0/cfg_data
}

# Slice the CFG bits to get the last 8 bits
cell pavel-demin:user:port_slicer cfg_slice_1 {
  DIN_WIDTH 16 DIN_FROM 15 DIN_TO 8
} {
  din hub_0/cfg_data
}

# Do an AND on the two slices
cell xilinx.com:ip:util_vector_logic and_0 {
  C_SIZE 8
  C_OPERATION and
} {
  Op1 cfg_slice_0/dout
  Op2 cfg_slice_1/dout
}

# Do a NOT on the result, output to STS
cell xilinx.com:ip:util_vector_logic not_0 {
  C_SIZE 8
  C_OPERATION not
} {
  Op1 and_0/Res
  Res hub_0/sts_data
}

## Send some probable signals out to the GPIO

# Concatenate for outputs
cell xilinx.com:ip:xlconcat:2.1 concat_0 {
  NUM_PORTS 3
} {
  In0 hub_0/cfg_data
  In1 not_0/Res
  In2 rst_0/peripheral_aresetn
  dout gpio0_tri_io
}

cell xilinx.com:ip:xlconcat:2.1 concat_1 {
  NUM_PORTS 3
} {
  In0 hub_0/cfg_data
  In1 not_0/Res
  In2 ps_0/FCLK_CLK0
  dout gpio1_tri_io
}
