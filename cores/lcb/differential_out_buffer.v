`timescale 1ns / 1ps

module lcb_differential_out_buffer #
(
  parameter integer DIFF_BUFFER_WIDTH = 1
)
(
  input   wire  [DIFF_BUFFER_WIDTH-1:0]   d_in,
  output  wire  [DIFF_BUFFER_WIDTH-1:0]   diff_out_p,
  output  wire  [DIFF_BUFFER_WIDTH-1:0]   diff_out_n
);

// Generate DIFF_BUFFER_WIDTH number of the Xilinx OBUFDS primitives
genvar i;
generate
  for (i = 0; i < DIFF_BUFFER_WIDTH; i = i + 1)
  begin : gen_diff_out
    OBUFDS
    #(
      .IOSTANDARD("DEFAULT")
    )
    obufds_inst
    (
      .I(d_in[i]),
      .O(diff_out_p[i]),
      .OB(diff_out_n[i])
    );
  end
endgenerate

endmodule
