`timescale 1ns / 1ps

// A wrapper for the Xilinx IBUFDS primitive with a parameterized width
module differential_in_buffer #
(
  parameter integer DIFF_BUFFER_WIDTH = 1
)
(
  input   wire  [DIFF_BUFFER_WIDTH-1:0]   diff_in_p,
  input   wire  [DIFF_BUFFER_WIDTH-1:0]   diff_in_n,
  output  wire  [DIFF_BUFFER_WIDTH-1:0]   d_out
);

// Generate DIFF_BUFFER_WIDTH number of the Xilinx IBUFDS primitives
genvar i;
generate
  for (i = 0; i < DIFF_BUFFER_WIDTH; i = i + 1)
  begin : gen_diff_in
    IBUFDS
    #(
      .IOSTANDARD("DEFAULT")
    )
    ibufds_inst
    (
      .I(diff_in_p[i]),
      .IB(diff_in_n[i]),
      .O(d_out[i])
    );
  end
endgenerate

endmodule
