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


# Create a FIFO block connected to the AXI hub
cell lcb:user:axis_fifo_sync fifo {
  WRITE_DEPTH 16
  ALWAYS_READY TRUE
  ALWAYS_VALID TRUE
} {
  aclk aclk
  S_AXIS s_axis
  M_AXIS m_axis
}

# Slice out the first CFG bit to be the FIFO's reset signal
cell pavel-demin:user:port_slicer rst_slice {
  DIN_WIDTH 32
  DIN_FROM 0
  DIN_TO 0
} {
  din cfg_word
}
# Negate it (active 1 from CFG)
# Do a NOT on the result, output to STS
cell xilinx.com:ip:util_vector_logic rst_n {
  C_SIZE 1
  C_OPERATION not
} {
  Op1 rst_slice/dout
  Res fifo/aresetn
}

## Concatenate the FIFO's status signals to the axi_hub's status signals

#  Read and write data width will only use the first 5 bits with a FIFO depth of 16, so slice it there
cell pavel-demin:user:port_slicer wr_cnt_slice {
  DIN_WIDTH 24
  DIN_FROM 4
  DIN_TO 0
} {
  din fifo/write_count
}
cell pavel-demin:user:port_slicer rd_cnt_slice {
  DIN_WIDTH 24
  DIN_FROM 4
  DIN_TO 0
} {
  din fifo/read_count
}

# If the overflow or underflow go high, latch until resetn deasserts
cell lcb:user:latch_high overflow_latch {
  WIDTH 1
} {
  din fifo/overflow
  clk aclk
  resetn rst_n/Res
}
cell lcb:user:latch_high underflow_latch {
  WIDTH 1
} {
  din fifo/underflow
  clk aclk
  resetn rst_n/Res
}


# 18 bit pad to make the status word 32 bits
cell xilinx.com:ip:xlconstant:1.1 sts_word_padding {
  CONST_VAL 0
  CONST_WIDTH 18
} {}

# Concatenate the status signals into a 32-bit word
cell xilinx.com:ip:xlconcat:2.1 sts_word {
  NUM_PORTS 7
} {
  In0 wr_cnt_slice/dout
  In1 fifo/full
  In2 overflow_latch/dout
  In3 rd_cnt_slice/dout
  In4 fifo/empty
  In5 underflow_latch/dout
  In6 sts_word_padding/dout
  dout sts_word
}
