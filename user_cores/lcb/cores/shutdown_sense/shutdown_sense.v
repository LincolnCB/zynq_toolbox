`timescale 1ns / 1ps

module shutdown_sense (
  input wire clk,
  input wire rst,
  input wire shutdown_sense_pin,
  output reg [2:0] shutdown_sense_sel,
  output reg [7:0] shutdown_sense
);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      // Reset logic
      shutdown_sense_sel <= 3'b000;
      shutdown_sense <= 8'b00000000;
    end else begin
      // Cycle through shutdown_sense_sel
      shutdown_sense_sel <= shutdown_sense_sel + 1;

      // Latch the corresponding bit of shutdown_sense
      if (shutdown_sense_pin) begin
        shutdown_sense[shutdown_sense_sel] <= 1'b1;
      end
    end
  end

endmodule
