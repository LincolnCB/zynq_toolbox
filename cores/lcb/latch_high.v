`timescale 1 ns / 1 ps

// A variable-width input latch that will bitwise latch any pulsed bits high until aresetn is deasserted.
// Parameters:
//  WIDTH: Width of the latch
module latch_high #(
  parameter integer WIDTH = 32
)(
  input  wire                          clk,
  input  wire                          resetn,
  input  wire [WIDTH-1:0]              din,
  output reg  [WIDTH-1:0]              dout
);
  always @(posedge clk) begin
    if (~resetn) begin
      dout <= {WIDTH{1'b0}};
    end else begin
      dout <= dout | din;
    end
  end
endmodule
