// filepath: /home/lcb-virt/Documents/rev_d_shim/cores/lcb/spi_cfg_sync.v
`timescale 1ns/1ps

module spi_cfg_sync (
  input  wire        clk,                // AXI clock
  input  wire        spi_clk,            // SPI clock
  input  wire        rst,                // Reset signal (active high)
  
  // Inputs from axi_shim_cfg
  input  wire [31:0] trig_lockout,
  input  wire [15:0] cal_offset,
  input  wire [15:0] dac_divider,
  input  wire [14:0] integ_thresh_avg,
  input  wire [31:0] integ_window,
  input  wire        integ_en,
  input  wire        spi_en,

  // Synchronized outputs
  output reg  [31:0] trig_lockout_stable,
  output reg  [15:0] cal_offset_stable,
  output reg  [15:0] dac_divider_stable,
  output reg  [14:0] integ_thresh_avg_stable,
  output reg  [31:0] integ_window_stable,
  output reg         integ_en_stable,
  output reg         spi_en_stable
);

  // Intermediate wires for synchronized signals
  wire [31:0] trig_lockout_sync;
  wire [15:0] cal_offset_sync;
  wire [15:0] dac_divider_sync;
  wire [15:0] integ_thresh_avg_sync;
  wire [31:0] integ_window_sync;
  wire        integ_en_sync;
  wire        spi_en_sync;

  // Stability signals for each synchronizer
  wire trig_lockout_stable_flag;
  wire cal_offset_stable_flag;
  wire dac_divider_stable_flag;
  wire integ_thresh_avg_stable_flag;
  wire integ_window_stable_flag;
  wire integ_en_stable_flag;
  wire spi_en_stable_flag;

  // Synchronize each signal using the synchronizer module
  synchronizer #(
    .DEPTH(3),
    .WIDTH(32),
    .STABLE_COUNT(2)
  ) sync_trig_lockout (
    .clk(spi_clk),
    .rst(rst),
    .din(trig_lockout),
    .dout(trig_lockout_sync),
    .stable(trig_lockout_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(16),
    .STABLE_COUNT(2)
  ) sync_cal_offset (
    .clk(spi_clk),
    .rst(rst),
    .din(cal_offset),
    .dout(cal_offset_sync),
    .stable(cal_offset_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(16),
    .STABLE_COUNT(2)
  ) sync_dac_divider (
    .clk(spi_clk),
    .rst(rst),
    .din(dac_divider),
    .dout(dac_divider_sync),
    .stable(dac_divider_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(16),
    .STABLE_COUNT(2)
  ) sync_integ_thresh_avg (
    .clk(spi_clk),
    .rst(rst),
    .din(integ_thresh_avg),
    .dout(integ_thresh_avg_sync),
    .stable(integ_thresh_avg_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(32),
    .STABLE_COUNT(2)
  ) sync_integ_window (
    .clk(spi_clk),
    .rst(rst),
    .din(integ_window),
    .dout(integ_window_sync),
    .stable(integ_window_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(1),
    .STABLE_COUNT(2)
  ) sync_integ_en (
    .clk(spi_clk),
    .rst(rst),
    .din(integ_en),
    .dout(integ_en_sync),
    .stable(integ_en_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(1),
    .STABLE_COUNT(2)
  ) sync_spi_en (
    .clk(spi_clk),
    .rst(rst),
    .din(spi_en),
    .dout(spi_en_sync),
    .stable(spi_en_stable_flag)
  );

  // Update stable registers when all signals are stable and spi_en_sync is high
  always @(posedge spi_clk or posedge rst) begin
    if (rst) begin
      trig_lockout_stable      <= 32'b0;
      cal_offset_stable        <= 16'b0;
      dac_divider_stable       <= 16'b0;
      integ_thresh_avg_stable  <= 16'b0;
      integ_window_stable      <= 32'b0;
      integ_en_stable          <= 1'b0;
      spi_en_stable            <= 1'b0;
    end else if (spi_en_sync && trig_lockout_stable_flag && cal_offset_stable_flag &&
                 dac_divider_stable_flag && integ_thresh_avg_stable_flag &&
                 integ_window_stable_flag && integ_en_stable_flag && spi_en_stable_flag) begin
      trig_lockout_stable      <= trig_lockout_sync;
      cal_offset_stable        <= cal_offset_sync;
      dac_divider_stable       <= dac_divider_sync;
      integ_thresh_avg_stable  <= integ_thresh_avg_sync;
      integ_window_stable      <= integ_window_sync;
      integ_en_stable          <= integ_en_sync;
      spi_en_stable            <= spi_en_sync;
    end
  end
endmodule
