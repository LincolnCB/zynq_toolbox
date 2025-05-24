// filepath: /home/lcb-virt/Documents/rev_d_shim/cores/lcb/spi_sts_sync.v
`timescale 1ns/1ps

module spi_sts_sync (
  input  wire        aclk,               // AXI clock
  input  wire        aresetn,            // Active low reset signal
  
  // Inputs from SPI domain
  input  wire        spi_off,
  input  wire [7:0]  dac_over_thresh,
  input  wire [7:0]  adc_over_thresh,
  input  wire [7:0]  dac_thresh_underflow,
  input  wire [7:0]  dac_thresh_overflow,
  input  wire [7:0]  adc_thresh_underflow,
  input  wire [7:0]  adc_thresh_overflow,
  input  wire [7:0]  dac_buf_underflow,
  input  wire [7:0]  adc_buf_overflow,
  input  wire [7:0]  unexp_dac_trig,
  input  wire [7:0]  unexp_adc_trig,

  // Synchronized outputs to AXI domain
  output reg         spi_off_stable,
  output reg  [7:0]  dac_over_thresh_stable,
  output reg  [7:0]  adc_over_thresh_stable,
  output reg  [7:0]  dac_thresh_underflow_stable,
  output reg  [7:0]  dac_thresh_overflow_stable,
  output reg  [7:0]  adc_thresh_underflow_stable,
  output reg  [7:0]  adc_thresh_overflow_stable,
  output reg  [7:0]  dac_buf_underflow_stable,
  output reg  [7:0]  adc_buf_overflow_stable,
  output reg  [7:0]  unexp_dac_trig_stable,
  output reg  [7:0]  unexp_adc_trig_stable
);

  // Intermediate wires for synchronized signals
  wire       spi_off_sync;
  wire [7:0] dac_over_thresh_sync;
  wire [7:0] adc_over_thresh_sync;
  wire [7:0] dac_thresh_underflow_sync;
  wire [7:0] dac_thresh_overflow_sync;
  wire [7:0] adc_thresh_underflow_sync;
  wire [7:0] adc_thresh_overflow_sync;
  wire [7:0] dac_buf_underflow_sync;
  wire [7:0] adc_buf_overflow_sync;
  wire [7:0] unexp_dac_trig_sync;
  wire [7:0] unexp_adc_trig_sync;

  // Stability signals for each synchronizer
  wire spi_off_stable_flag;
  wire dac_over_thresh_stable_flag;
  wire adc_over_thresh_stable_flag;
  wire dac_thresh_underflow_stable_flag;
  wire dac_thresh_overflow_stable_flag;
  wire adc_thresh_underflow_stable_flag;
  wire adc_thresh_overflow_stable_flag;
  wire dac_buf_underflow_stable_flag;
  wire adc_buf_overflow_stable_flag;
  wire unexp_dac_trig_stable_flag;
  wire unexp_adc_trig_stable_flag;

  // Synchronize each signal using the synchronizer module
  synchronizer #(
    .DEPTH(3),
    .WIDTH(1),
    .STABLE_COUNT(2)
  ) sync_spi_off (
    .clk(aclk),
    .aresetn(aresetn),
    .din(spi_off),
    .dout(spi_off_sync),
    .stable(spi_off_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_dac_over_thresh (
    .clk(aclk),
    .aresetn(aresetn),
    .din(dac_over_thresh),
    .dout(dac_over_thresh_sync),
    .stable(dac_over_thresh_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_adc_over_thresh (
    .clk(aclk),
    .aresetn(aresetn),
    .din(adc_over_thresh),
    .dout(adc_over_thresh_sync),
    .stable(adc_over_thresh_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_dac_thresh_underflow (
    .clk(aclk),
    .aresetn(aresetn),
    .din(dac_thresh_underflow),
    .dout(dac_thresh_underflow_sync),
    .stable(dac_thresh_underflow_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_dac_thresh_overflow (
    .clk(aclk),
    .aresetn(aresetn),
    .din(dac_thresh_overflow),
    .dout(dac_thresh_overflow_sync),
    .stable(dac_thresh_overflow_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_adc_thresh_underflow (
    .clk(aclk),
    .aresetn(aresetn),
    .din(adc_thresh_underflow),
    .dout(adc_thresh_underflow_sync),
    .stable(adc_thresh_underflow_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_adc_thresh_overflow (
    .clk(aclk),
    .aresetn(aresetn),
    .din(adc_thresh_overflow),
    .dout(adc_thresh_overflow_sync),
    .stable(adc_thresh_overflow_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_dac_buf_underflow (
    .clk(aclk),
    .aresetn(aresetn),
    .din(dac_buf_underflow),
    .dout(dac_buf_underflow_sync),
    .stable(dac_buf_underflow_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_adc_buf_overflow (
    .clk(aclk),
    .aresetn(aresetn),
    .din(adc_buf_overflow),
    .dout(adc_buf_overflow_sync),
    .stable(adc_buf_overflow_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_unexp_dac_trig (
    .clk(aclk),
    .aresetn(aresetn),
    .din(unexp_dac_trig),
    .dout(unexp_dac_trig_sync),
    .stable(unexp_dac_trig_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_unexp_adc_trig (
    .clk(aclk),
    .aresetn(aresetn),
    .din(unexp_adc_trig),
    .dout(unexp_adc_trig_sync),
    .stable(unexp_adc_trig_stable_flag)
  );

  // Update stable registers for each signal individually
  always @(posedge aclk) begin
    spi_off_stable               <= spi_off_stable_flag               ? spi_off_sync               : 1'b0;
    dac_over_thresh_stable       <= dac_over_thresh_stable_flag       ? dac_over_thresh_sync       : 8'b0;
    adc_over_thresh_stable       <= adc_over_thresh_stable_flag       ? adc_over_thresh_sync       : 8'b0;
    dac_thresh_underflow_stable  <= dac_thresh_underflow_stable_flag  ? dac_thresh_underflow_sync  : 8'b0;
    dac_thresh_overflow_stable   <= dac_thresh_overflow_stable_flag   ? dac_thresh_overflow_sync   : 8'b0;
    adc_thresh_underflow_stable  <= adc_thresh_underflow_stable_flag  ? adc_thresh_underflow_sync  : 8'b0;
    adc_thresh_overflow_stable   <= adc_thresh_overflow_stable_flag   ? adc_thresh_overflow_sync   : 8'b0;
    dac_buf_underflow_stable     <= dac_buf_underflow_stable_flag     ? dac_buf_underflow_sync     : 8'b0;
    adc_buf_overflow_stable      <= adc_buf_overflow_stable_flag      ? adc_buf_overflow_sync      : 8'b0;
    unexp_dac_trig_stable        <= unexp_dac_trig_stable_flag        ? unexp_dac_trig_sync        : 8'b0;
    unexp_adc_trig_stable        <= unexp_adc_trig_stable_flag        ? unexp_adc_trig_sync        : 8'b0;
  end
endmodule

