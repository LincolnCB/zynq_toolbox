## Instantiate the processing system and connect it to fixed IO and DDR

# Create the PS (processing_system7)
# 0: Don't use board preset
# {}: No additional CFG parameters
init_ps ps_0 0 {} {
  M_AXI_GP0_ACLK ps_0/FCLK_CLK0
}


## Create the reset hub

# Create xlconstant to hold reset high (active low)
cell xilinx.com:ip:xlconstant const_0
# Create proc_sys_reset
# - Resetn is constant low (active high)
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
  S_AXI ps_0/M_AXI_GP0
  aclk ps_0/FCLK_CLK0
  aresetn rst_0/peripheral_aresetn
}

# Assign the address of the axi_hub in the PS address space
# - Offset: 0x40000000
# - Range: 128M (to 0x47FFFFFF)
# - Subordinate Port: hub_0/S_AXI
addr 0x40000000 128M hub_0/S_AXI

## Add a vector nand gate (see source file)
module fifo_0 {
  source projects/example_axi_hub_regs/nand.tcl
} {
  nand_din_concat hub_0/cfg_data
  nand_res hub_0/sts_data
}
