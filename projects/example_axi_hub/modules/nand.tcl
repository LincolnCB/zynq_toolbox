# 64-bit concatenated inputs to NAND
create_bd_pin -dir I -from 63 -to 0 nand_din_concat
# 32-bit Status word
create_bd_pin -dir O -from 31 -to 0 nand_res

# Slice the input to get the first 32 bits
cell pavel-demin:user:port_slicer din_slice_0 {
  DIN_WIDTH 64 DIN_FROM 31 DIN_TO 0
} {
  din nand_din_concat
}
# Slice the input to get the last 32 bits
cell pavel-demin:user:port_slicer din_slice_1 {
  DIN_WIDTH 64 DIN_FROM 63 DIN_TO 32
} {
  din nand_din_concat
}
# Do an AND on the two slices
cell xilinx.com:ip:util_vector_logic and_op {
  C_SIZE 32
  C_OPERATION and
} {
  Op1 din_slice_0/dout
  Op2 din_slice_1/dout
}
# Do a NOT on the result, output to nand_res
cell xilinx.com:ip:util_vector_logic not_op {
  C_SIZE 32
  C_OPERATION not
} {
  Op1 and_op/Res
  Res nand_res
}
