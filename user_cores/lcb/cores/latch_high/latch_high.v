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
  output wire [WIDTH-1:0]              dout
);
  reg [WIDTH-1:0] latch;

  assign dout = latch | din;

  always @(posedge clk or negedge resetn) begin
    if (~resetn) begin
      latch <= {WIDTH{1'b0}};
    end else begin
      latch <= latch | din;
    end
  end
endmodule
