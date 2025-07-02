// filepath: /home/lcb-virt/Documents/rev_d_shim/cores/lcb/spi_cfg_sync.v
`timescale 1ns/1ps

module shim_spi_cfg_sync (
  input  wire        spi_clk,             // SPI clock
  input  wire        sync_resetn,         // Active low reset

  // Inputs from axi_shim_cfg (AXI domain)
  input  wire [14:0] integ_thresh_avg,
  input  wire [31:0] integ_window,
  input  wire        integ_en,
  input  wire        spi_en,
  input  wire        block_buffers,

  // Synchronized outputs to SPI domain
  output reg  [14:0] integ_thresh_avg_stable,
  output reg  [31:0] integ_window_stable,
  output reg         integ_en_stable,
  output reg         spi_en_stable,
  output reg         block_buffers_stable
);

  // Intermediate wires for synchronized signals
  wire [14:0] integ_thresh_avg_sync;
  wire [31:0] integ_window_sync;
  wire        integ_en_sync;
  wire        spi_en_sync;
  wire        block_buffers_sync;

  // Stability signals for each synchronizer
  wire integ_thresh_avg_stable_flag;
  wire integ_window_stable_flag;
  wire integ_en_stable_flag;
  wire spi_en_stable_flag;
  wire block_buffers_stable_flag;

  // Synchronize each signal using the synchronizer module
  synchronizer #(
    .DEPTH(3),
    .WIDTH(15),
    .STABLE_COUNT(2)
  ) sync_integ_thresh_avg (
    .clk(spi_clk),
    .resetn(spi_resetn),
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
    .resetn(spi_resetn),
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
    .resetn(spi_resetn),
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
    .resetn(spi_resetn),
    .din(spi_en),
    .dout(spi_en_sync),
    .stable(spi_en_stable_flag)
  );

  synchronizer #(
    .DEPTH(3),
    .WIDTH(1),
    .STABLE_COUNT(2)
  ) sync_block_buffers (
    .clk(spi_clk),
    .resetn(spi_resetn),
    .din(block_buffers),
    .dout(block_buffers_sync),
    .stable(block_buffers_stable_flag)
  );

  // Update stable registers when all signals are stable and spi_en_sync is high
  always @(posedge spi_clk) begin
    if (!sync_resetn) begin
      integ_thresh_avg_stable  <= 15'b0;
      integ_window_stable      <= 32'b0;
      integ_en_stable          <= 1'b0;
      block_buffers_stable     <= 1'b1;
      spi_en_stable            <= 1'b0;
    end else if (spi_en_sync && spi_en_stable_flag) begin
      // Update all the configuration registers only when spi_en_sync is high and they're stable
      if (integ_thresh_avg_stable_flag
          && integ_window_stable_flag 
          && integ_en_stable_flag) begin
        integ_thresh_avg_stable  <= integ_thresh_avg_sync;
        integ_window_stable      <= integ_window_sync;
        integ_en_stable          <= integ_en_sync;
        spi_en_stable            <= spi_en_sync;
      end
      // Update block_buffers_stable regardless of other flags
      if (block_buffers_stable_flag) block_buffers_stable <= block_buffers_sync;
    end
  end
endmodule
