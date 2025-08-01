`timescale 1ns/1ps

module shim_spi_cfg_sync (
  input  wire        aclk,       // AXI domain clock
  input  wire        aresetn,    // Active low reset signal
  input  wire        spi_clk,    // SPI domain clock
  input  wire        spi_resetn, // Active low reset signal for SPI domain

  // Inputs from axi_shim_cfg (AXI domain)
  input  wire [14:0] integ_thresh_avg,
  input  wire [31:0] integ_window,
  input  wire        integ_en,
  input  wire        spi_en,
  input  wire        block_buffers,

  // Synchronized outputs to SPI domain
  output wire [14:0] integ_thresh_avg_sync,
  output wire [31:0] integ_window_sync,
  output wire        integ_en_sync,
  output wire        spi_en_sync,
  output wire        block_buffers_sync
);

  // Default values for registers
  localparam [14:0] integ_thresh_avg_default = 15'h1000;
  localparam [31:0] integ_window_default = 32'h00010000;
  localparam integ_en_default = 1'b0;
  localparam spi_en_default = 1'b0;
  localparam block_buffers_default = 1'b1;

  // Stability signals for each synchronizer
  wire integ_thresh_avg_stable_flag;
  wire integ_window_stable_flag;
  wire integ_en_stable_flag;
  wire spi_en_stable_flag;
  wire block_buffers_stable_flag;

  // Synchronize each signal using the sync_coherent module

  sync_coherent #(
    .WIDTH(15)
  ) sync_integ_thresh_avg (
    .in_clk(aclk),
    .in_resetn(aresetn),
    .out_clk(spi_clk),
    .out_resetn(spi_resetn),
    .din(integ_thresh_avg),
    .dout(integ_thresh_avg_sync),
    .dout_default(integ_thresh_avg_default)
  );

  sync_coherent #(
    .WIDTH(32)
  ) sync_integ_window (
    .in_clk(aclk),
    .in_resetn(aresetn),
    .out_clk(spi_clk),
    .out_resetn(spi_resetn),
    .din(integ_window),
    .dout(integ_window_sync),
    .dout_default(integ_window_default)
  );

  sync_coherent #(
    .WIDTH(1)
  ) sync_integ_en (
    .in_clk(aclk),
    .in_resetn(aresetn),
    .out_clk(spi_clk),
    .out_resetn(spi_resetn),
    .din(integ_en),
    .dout(integ_en_sync),
    .dout_default(integ_en_default)
  );

  sync_coherent #(
    .WIDTH(1)
  ) sync_spi_en (
    .in_clk(aclk),
    .in_resetn(aresetn),
    .out_clk(spi_clk),
    .out_resetn(spi_resetn),
    .din(spi_en),
    .dout(spi_en_sync),
    .dout_default(spi_en_default)
  );

  sync_coherent #(
    .WIDTH(1)
  ) sync_block_buffers (
    .in_clk(aclk),
    .in_resetn(aresetn),
    .out_clk(spi_clk),
    .out_resetn(spi_resetn),
    .din(block_buffers),
    .dout(block_buffers_sync),
    .dout_default(block_buffers_default)
  );
  
endmodule
