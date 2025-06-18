## FIFO Module with 32-bit CFG and STS connections

# Ports to connect:
# S_AXIS: AXI Stream Subordinate interface
create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 s_axis
# M_AXIS: AXI Stream Manager interface
create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 m_axis
# Clock
create_bd_pin -dir I aclk
# 32-bit Configuration word
create_bd_pin -dir I -from 31 -to 0 cfg_word
# 32-bit Status word
create_bd_pin -dir O -from 31 -to 0 sts_word

##################################################

## Synchronous FIFO with AXI Stream interface

## Reset signal handling
# Slice out the first CFG bit to be the FIFO's reset signal
cell xilinx.com:ip:xlslice:1.0 rst_slice {
  DIN_WIDTH 32
  DIN_FROM 0
  DIN_TO 0
} {
  din cfg_word
}
# Reset manager
# Use aux_reset to allow for manual customizable low/high active
cell xilinx.com:ip:proc_sys_reset:5.0 fifo_rst {
  C_AUX_RESET_HIGH.VALUE_SRC USER
  C_AUX_RESET_HIGH 1
} {
  aux_reset_in rst_slice/dout
  slowest_sync_clk aclk
}

## Custom FIFO to allow for extra status signals
# AXI Stream interface
cell lcb:user:axis_fifo_bridge axis_fifo_bridge {} {
  aclk aclk
  aresetn fifo_rst/peripheral_aresetn
  s_axis s_axis
  m_axis m_axis
}
# FIFO
cell lcb:user:fifo_sync fifo {
  DATA_WIDTH 32
  ADDR_WIDTH 5
} {
  clk aclk
  resetn fifo_rst/peripheral_aresetn
  wr_data axis_fifo_bridge/fifo_wr_data
  wr_en axis_fifo_bridge/fifo_wr_en
  fifo_full axis_fifo_bridge/fifo_full
  rd_data axis_fifo_bridge/fifo_rd_data
  rd_en axis_fifo_bridge/fifo_rd_en
  fifo_empty axis_fifo_bridge/fifo_empty
}

## Concatenate the FIFO's status signals to the axi_hub's status signals
# 18 bit pad to make the status word 32 bits
cell xilinx.com:ip:xlconstant:1.1 sts_word_padding {
  CONST_VAL 0
  CONST_WIDTH 18
} {}
# Concatenate the status signals into a 32-bit word
cell xilinx.com:ip:xlconcat:2.1 sts_word {
  NUM_PORTS 7
} {
  In0 fifo/fifo_count
  In1 fifo/full
  In2 axis_fifo_bridge/fifo_overflow
  In3 fifo/fifo_count
  In4 fifo/empty
  In5 axis_fifo_bridge/fifo_underflow
  In6 sts_word_padding/dout
  dout sts_word
}
