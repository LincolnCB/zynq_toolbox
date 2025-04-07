// filepath: /home/lcb-virt/Documents/rev_d_shim/cores/lcb/spi_sts_sync.v
`timescale 1ns/1ps

module spi_sts_sync (
  input  wire        clk,                // AXI clock
  input  wire        spi_clk,            // SPI clock
  input  wire        rst,                // Reset signal (active high)
  
  // Inputs from SPI domain
  input  wire        spi_running,
  input  wire [7:0]  dac_over_thresh,
  input  wire [7:0]  adc_over_thresh,
  input  wire [7:0]  dac_thresh_underflow,
  input  wire [7:0]  dac_thresh_overflow,
  input  wire [7:0]  adc_thresh_underflow,
  input  wire [7:0]  adc_thresh_overflow,
  input  wire [7:0]  dac_buf_underflow,
  input  wire [7:0]  adc_buf_overflow,
  input  wire [7:0]  premat_dac_trig,
  input  wire [7:0]  premat_adc_trig,
  input  wire [7:0]  premat_dac_div,
  input  wire [7:0]  premat_adc_div,

  // Synchronized outputs to AXI domain
  output reg         spi_running_stable,
  output reg  [7:0]  dac_over_thresh_stable,
  output reg  [7:0]  adc_over_thresh_stable,
  output reg  [7:0]  dac_thresh_underflow_stable,
  output reg  [7:0]  dac_thresh_overflow_stable,
  output reg  [7:0]  adc_thresh_underflow_stable,
  output reg  [7:0]  adc_thresh_overflow_stable,
  output reg  [7:0]  dac_buf_underflow_stable,
  output reg  [7:0]  adc_buf_overflow_stable,
  output reg  [7:0]  premat_dac_trig_stable,
  output reg  [7:0]  premat_adc_trig_stable,
  output reg  [7:0]  premat_dac_div_stable,
  output reg  [7:0]  premat_adc_div_stable
);

  // Intermediate wires for synchronized signals
  wire       spi_running_sync;
  wire [7:0] dac_over_thresh_sync;
  wire [7:0] adc_over_thresh_sync;
  wire [7:0] dac_thresh_underflow_sync;
  wire [7:0] dac_thresh_overflow_sync;
  wire [7:0] adc_thresh_underflow_sync;
  wire [7:0] adc_thresh_overflow_sync;
  wire [7:0] dac_buf_underflow_sync;
  wire [7:0] adc_buf_overflow_sync;
  wire [7:0] premat_dac_trig_sync;
  wire [7:0] premat_adc_trig_sync;
  wire [7:0] premat_dac_div_sync;
  wire [7:0] premat_adc_div_sync;

  // Stability signals for each synchronizer
  wire spi_running_stable_flag;
  wire dac_over_thresh_stable_flag;
  wire adc_over_thresh_stable_flag;
  wire dac_thresh_underflow_stable_flag;
  wire dac_thresh_overflow_stable_flag;
  wire adc_thresh_underflow_stable_flag;
  wire adc_thresh_overflow_stable_flag;
  wire dac_buf_underflow_stable_flag;
  wire adc_buf_overflow_stable_flag;
  wire premat_dac_trig_stable_flag;
  wire premat_adc_trig_stable_flag;
  wire premat_dac_div_stable_flag;
  wire premat_adc_div_stable_flag;

  // Synchronize each signal using the synchronizer module
  synchronizer #(
    .DEPTH(3),
    .WIDTH(1),
    .STABLE_COUNT(2)
  ) sync_spi_running (
    .clk(clk),
    .rst(rst),
    .din(spi_running),
    .dout(spi_running_sync),
    .stable(spi_running_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_dac_over_thresh (
    .clk(clk),
    .rst(rst),
    .din(dac_over_thresh),
    .dout(dac_over_thresh_sync),
    .stable(dac_over_thresh_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_adc_over_thresh (
    .clk(clk),
    .rst(rst),
    .din(adc_over_thresh),
    .dout(adc_over_thresh_sync),
    .stable(adc_over_thresh_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_dac_thresh_underflow (
    .clk(clk),
    .rst(rst),
    .din(dac_thresh_underflow),
    .dout(dac_thresh_underflow_sync),
    .stable(dac_thresh_underflow_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_dac_thresh_overflow (
    .clk(clk),
    .rst(rst),
    .din(dac_thresh_overflow),
    .dout(dac_thresh_overflow_sync),
    .stable(dac_thresh_overflow_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_adc_thresh_underflow (
    .clk(clk),
    .rst(rst),
    .din(adc_thresh_underflow),
    .dout(adc_thresh_underflow_sync),
    .stable(adc_thresh_underflow_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_adc_thresh_overflow (
    .clk(clk),
    .rst(rst),
    .din(adc_thresh_overflow),
    .dout(adc_thresh_overflow_sync),
    .stable(adc_thresh_overflow_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_dac_buf_underflow (
    .clk(clk),
    .rst(rst),
    .din(dac_buf_underflow),
    .dout(dac_buf_underflow_sync),
    .stable(dac_buf_underflow_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_adc_buf_overflow (
    .clk(clk),
    .rst(rst),
    .din(adc_buf_overflow),
    .dout(adc_buf_overflow_sync),
    .stable(adc_buf_overflow_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_premat_dac_trig (
    .clk(clk),
    .rst(rst),
    .din(premat_dac_trig),
    .dout(premat_dac_trig_sync),
    .stable(premat_dac_trig_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_premat_adc_trig (
    .clk(clk),
    .rst(rst),
    .din(premat_adc_trig),
    .dout(premat_adc_trig_sync),
    .stable(premat_adc_trig_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_premat_dac_div (
    .clk(clk),
    .rst(rst),
    .din(premat_dac_div),
    .dout(premat_dac_div_sync),
    .stable(premat_dac_div_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_premat_adc_div (
    .clk(clk),
    .rst(rst),
    .din(premat_adc_div),
    .dout(premat_adc_div_sync),
    .stable(premat_adc_div_stable_flag)
  );

  // Update stable registers for each signal individually
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      spi_running_stable          <= 1'b0;
      dac_over_thresh_stable      <= 8'b0;
      adc_over_thresh_stable      <= 8'b0;
      dac_thresh_underflow_stable <= 8'b0;
      dac_thresh_overflow_stable  <= 8'b0;
      adc_thresh_underflow_stable <= 8'b0;
      adc_thresh_overflow_stable  <= 8'b0;
      dac_buf_underflow_stable    <= 8'b0;
      adc_buf_overflow_stable     <= 8'b0;
      premat_dac_trig_stable      <= 8'b0;
      premat_adc_trig_stable      <= 8'b0;
      premat_dac_div_stable       <= 8'b0;
      premat_adc_div_stable       <= 8'b0;
    end else begin
      if (spi_running_stable_flag)
        spi_running_stable <= spi_running_sync;
      if (dac_over_thresh_stable_flag)
        dac_over_thresh_stable <= dac_over_thresh_sync;
      if (adc_over_thresh_stable_flag)
        adc_over_thresh_stable <= adc_over_thresh_sync;
      if (dac_thresh_underflow_stable_flag)
        dac_thresh_underflow_stable <= dac_thresh_underflow_sync;
      if (dac_thresh_overflow_stable_flag)
        dac_thresh_overflow_stable <= dac_thresh_overflow_sync;
      if (adc_thresh_underflow_stable_flag)
        adc_thresh_underflow_stable <= adc_thresh_underflow_sync;
      if (adc_thresh_overflow_stable_flag)
        adc_thresh_overflow_stable <= adc_thresh_overflow_sync;
      if (dac_buf_underflow_stable_flag)
        dac_buf_underflow_stable <= dac_buf_underflow_sync;
      if (adc_buf_overflow_stable_flag)
        adc_buf_overflow_stable <= adc_buf_overflow_sync;
      if (premat_dac_trig_stable_flag)
        premat_dac_trig_stable <= premat_dac_trig_sync;
      if (premat_adc_trig_stable_flag)
        premat_adc_trig_stable <= premat_adc_trig_sync;
      if (premat_dac_div_stable_flag)
        premat_dac_div_stable <= premat_dac_div_sync;
      if (premat_adc_div_stable_flag)
        premat_adc_div_stable <= premat_adc_div_sync;
    end
  end
endmodule
