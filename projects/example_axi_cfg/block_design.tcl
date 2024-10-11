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
# - Config width is 64 bits, first 32 are NANDed with last 32
# - Status width is 32 bits, output of NAND
# - Connect the axi_hub to the processing system's GP AXI 0 interface
# - Connect the axi_hub to the processing system's clock and the reset hub
cell pavel-demin:user:axi_hub hub_0 {
  CFG_DATA_WIDTH 64
  STS_DATA_WIDTH 32
} {
  aclk ps_0/FCLK_CLK0
  aresetn rst_0/peripheral_aresetn
}

# Assign the address of the axi_hub in the PS address space
# - Offset: 0x40000000
# - Range: 128M (to 0x47FFFFFF)
# - Subordinate Port: hub_0/S_AXI
# - Manager Port (needs / prefix): /ps_0/M_AXI_GP0
addr 0x40000000 128M hub_0/S_AXI /ps_0/M_AXI_GP0

## Do a NAND on the CFG bits and output to STS

# Slice the CFG bits to get the first 32 bits
cell pavel-demin:user:port_slicer cfg_slice_0 {
  DIN_WIDTH 64 DIN_FROM 31 DIN_TO 0
} {
  din hub_0/cfg_data
}

# Slice the CFG bits to get the last 32 bits
cell pavel-demin:user:port_slicer cfg_slice_1 {
  DIN_WIDTH 64 DIN_FROM 63 DIN_TO 32
} {
  din hub_0/cfg_data
}

# Do an AND on the two slices
cell xilinx.com:ip:util_vector_logic and_0 {
  C_SIZE 32
  C_OPERATION and
} {
  Op1 cfg_slice_0/dout
  Op2 cfg_slice_1/dout
}

# Do a NOT on the result, output to STS
cell xilinx.com:ip:util_vector_logic not_0 {
  C_SIZE 32
  C_OPERATION not
} {
  Op1 and_0/Res
  Res hub_0/sts_data
}
