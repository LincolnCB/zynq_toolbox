############# General setup #############

## Instantiate the processing system

# Create the PS (processing_system7)
# 1: Use board preset
# Config:
# - Unused AXI ACP port disabled
# Connections:
# - GP AXI 0 (Master) clock is connected to the processing system's first clock, FCLK_CLK0
init_ps ps_0 1 {
  PCW_USE_S_AXI_ACP 0
} {
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
# - Config width is 96 bits
#     63:0 are used for NAND example
#     95:64 are used for FIFO control
# - Status width is 64 bits
#     31:0 are used for NAND example
#     63:32 are used for FIFO status
# - Connect the axi_hub to the processing system's GP AXI 0 interface
# - Connect the axi_hub to the processing system's clock and the reset hub
cell pavel-demin:user:axi_hub hub_0 {
  CFG_DATA_WIDTH 96
  STS_DATA_WIDTH 64
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



############# FIFO and BRAM for this project #############

## Add a FIFO loopback on AXI hub port 0

# Slice off CFG 95:64 for FIFO control
cell pavel-demin:user:port_slicer fifo_0_cfg {
  DIN_WIDTH 96 DIN_FROM 95 DIN_TO 64
} {
  din hub_0/cfg_data
}
# Create a FIFO block connected to the AXI hub (see source file)
module fifo_0 {
  source projects/example_axi_hub/modules/fifo.tcl
} {
  aclk ps_0/FCLK_CLK0
  s_axis hub_0/M00_AXIS
  m_axis hub_0/S00_AXIS
  cfg_word fifo_0_cfg/dout
}


## Add a BRAM on AXI hub port 1

# There are 140 36Kib (36864 bit) BRAM blocks in the Zynq-7020
# This block has 16384 32-bit words, 512Kib (524288 bits)
# Because of the 32-bit width, this utilizes 16 36Kib blocks
cell xilinx.com:ip:blk_mem_gen bram_0 {
  MEMORY_TYPE True_Dual_Port_RAM
  USE_BRAM_BLOCK Stand_Alone
  USE_BYTE_WRITE_ENABLE true
  BYTE_SIZE 8
  WRITE_WIDTH_A 32
  WRITE_DEPTH_A 16384
  WRITE_WIDTH_B 32
  REGISTER_PORTA_OUTPUT_OF_MEMORY_PRIMITIVES false
  REGISTER_PORTB_OUTPUT_OF_MEMORY_PRIMITIVES false
} {
  BRAM_PORTA hub_0/B01_BRAM
}



############# Simple Register Tests #############
# Uses the first 64 bits of the CFG data and the first 32 bits of the STS data
# This is a simple test to verify that the registers are working
# The first 32 bits of the STS data are the bitwise NAND 
#   of the first 32 bits and the second 32 bits of the CFG data

# Slice off CFG 63:0 for NAND input
cell pavel-demin:user:port_slicer nand_0_cfg {
  DIN_WIDTH 96 DIN_FROM 63 DIN_TO 0
} {
  din hub_0/cfg_data
}
# Add a vector nand gate (see source file)
module nand_0 {
  source projects/example_axi_hub/modules/nand.tcl
} {
  nand_din_concat nand_0_cfg/dout
}



############# Concatenate all status signals #############
cell xilinx.com:ip:xlconcat:2.1 sts_concat {
  NUM_PORTS 2
} {
  In0 nand_0/nand_res
  In1 fifo_0/sts_word
  dout hub_0/sts_data
}
