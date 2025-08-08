`timescale 1ns/1ps

module shim_spi_cfg_sync (
  input  wire        aclk,       // AXI domain clock
  input  wire        aresetn,    // Active low reset signal
  input  wire        spi_clk,    // SPI domain clock
  input  wire        spi_resetn, // Active low reset signal for SPI domain

  // Inputs from axi_shim_cfg (AXI domain)
  input  wire        spi_en,
  input  wire        block_buffers,
  input  wire [14:0] integ_thresh_avg,
  input  wire [31:0] integ_window,
  input  wire        integ_en,
  input  wire [15:0] boot_test_skip,

  // Synchronized outputs to SPI domain
  output wire        spi_en_sync,
  output wire        block_buffers_sync,
  output wire [14:0] integ_thresh_avg_sync,
  output wire [31:0] integ_window_sync,
  output wire        integ_en_sync,
  output wire [15:0] boot_test_skip_sync
);

  // Default values for registers
  localparam [14:0] integ_thresh_avg_default = 15'h1000;
  localparam [31:0] integ_window_default = 32'h00010000;

  // Synchronize each signal
  // Use sync_coherent for multi-bit data,
  //   sync_incoherent for data where individual bits are not coherent with each other

  // SPI enable (incoherent)
  sync_incoherent #(
    .WIDTH(1)
  ) sync_spi_en (
    .clk(spi_clk),
    .resetn(spi_resetn),
    .din(spi_en),
    .dout(spi_en_sync)
  );

  // Block buffers (incoherent)
  sync_incoherent #(
    .WIDTH(1)
  ) sync_block_buffers (
    .clk(spi_clk),
    .resetn(spi_resetn),
    .din(block_buffers),
    .dout(block_buffers_sync)
  );
  
  // Integrator enable (incoherent)
  sync_incoherent #(
    .WIDTH(1)
  ) sync_integ_en (
    .clk(spi_clk),
    .resetn(spi_resetn),
    .din(integ_en),
    .dout(integ_en_sync)
  );

  // Integrator threshold average (coherent)
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

  // Integrator window (coherent)
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

  // Boot test skip (incoherent)
  sync_incoherent #(
    .WIDTH(16)
  ) sync_boot_test_skip (
    .clk(spi_clk),
    .resetn(spi_resetn),
    .din(boot_test_skip),
    .dout(boot_test_skip_sync)
  );
  
endmodule
