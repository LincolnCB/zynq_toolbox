`timescale 1ns / 1ps


module AND_gate(
  input   wire    in_a,
  input   wire    in_b,
  output  wire    out_and
);

  assign out_and = in_a & in_b;

endmodule
