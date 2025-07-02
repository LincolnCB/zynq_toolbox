`timescale 1ns/1ps

module shim_spi_sts_sync (
  input  wire        aclk,               // AXI clock
  input  wire        aresetn,            // Active low reset signal
  
  //// Inputs from SPI domain
  // SPI system status
  input  wire        spi_off,
  // Integrator threshold status
  input  wire [7:0]  over_thresh,
  input  wire [7:0]  thresh_underflow,
  input  wire [7:0]  thresh_overflow,
  // Trigger channel status
  input  wire        bad_trig_cmd,
  input  wire        trig_data_buf_overflow,
  // DAC channel status
  input  wire [7:0]  dac_boot_fail,
  input  wire [7:0]  bad_dac_cmd,
  input  wire [7:0]  dac_cal_oob,
  input  wire [7:0]  dac_val_oob,
  input  wire [7:0]  dac_cmd_buf_underflow,
  input  wire [7:0]  unexp_dac_trig,
  // ADC channel status
  input  wire [7:0]  adc_boot_fail,
  input  wire [7:0]  bad_adc_cmd,
  input  wire [7:0]  adc_cmd_buf_underflow,
  input  wire [7:0]  adc_data_buf_overflow,
  input  wire [7:0]  unexp_adc_trig,

  //// Synchronized outputs to AXI domain
  // SPI system status
  output reg         spi_off_stable,
  // Integrator threshold status
  output reg  [7:0]  over_thresh_stable,
  output reg  [7:0]  thresh_underflow_stable,
  output reg  [7:0]  thresh_overflow_stable,
  // Trigger channel status
  output reg         bad_trig_cmd_stable,
  output reg         trig_data_buf_overflow_stable,
  // DAC channel status
  output reg  [7:0]  dac_boot_fail_stable,
  output reg  [7:0]  bad_dac_cmd_stable,
  output reg  [7:0]  dac_cal_oob_stable,
  output reg  [7:0]  dac_val_oob_stable,
  output reg  [7:0]  dac_cmd_buf_underflow_stable,
  output reg  [7:0]  unexp_dac_trig_stable,
  // ADC channel status
  output reg  [7:0]  adc_boot_fail_stable,
  output reg  [7:0]  bad_adc_cmd_stable,
  output reg  [7:0]  adc_cmd_buf_underflow_stable,
  output reg  [7:0]  adc_data_buf_overflow_stable,
  output reg  [7:0]  unexp_adc_trig_stable
);

  //// Intermediate wires for synchronized signals
  // SPI system status
  wire       spi_off_sync;
  // Integrator threshold status
  wire [7:0] over_thresh_sync;
  wire [7:0] thresh_underflow_sync;
  wire [7:0] thresh_overflow_sync;
  // Trigger channel status
  wire       bad_trig_cmd_sync;
  wire       trig_data_buf_overflow_sync;
  // DAC channel status
  wire [7:0] dac_boot_fail_sync;
  wire [7:0] bad_dac_cmd_sync;
  wire [7:0] dac_cal_oob_sync;
  wire [7:0] dac_val_oob_sync;
  wire [7:0] dac_cmd_buf_underflow_sync;
  wire [7:0] unexp_dac_trig_sync;
  // ADC channel status
  wire [7:0] adc_boot_fail_sync;
  wire [7:0] bad_adc_cmd_sync;
  wire [7:0] adc_cmd_buf_underflow_sync;
  wire [7:0] adc_data_buf_overflow_sync;
  wire [7:0] unexp_adc_trig_sync;

  //// Stability signals for each synchronizer
  // SPI system status
  wire spi_off_stable_flag;
  // Integrator threshold status
  wire over_thresh_stable_flag;
  wire thresh_underflow_stable_flag;
  wire thresh_overflow_stable_flag;
  // Trigger channel status
  wire bad_trig_cmd_stable_flag;
  wire trig_data_buf_overflow_stable_flag;
  // DAC channel status
  wire [7:0] dac_boot_fail_stable;
  wire bad_dac_cmd_stable_flag;
  wire dac_cal_oob_stable_flag;
  wire dac_val_oob_stable_flag;
  wire dac_cmd_buf_underflow_stable_flag;
  wire unexp_dac_trig_stable_flag;
  // ADC channel status
  wire [7:0] adc_boot_fail_stable;
  wire bad_adc_cmd_stable_flag;
  wire adc_cmd_buf_underflow_stable_flag;
  wire adc_data_buf_overflow_stable_flag;
  wire unexp_adc_trig_stable_flag;

  //// Synchronize each signal using a synchronizer module
  // SPI system status
  synchronizer #(
    .DEPTH(3),
    .WIDTH(1),
    .STABLE_COUNT(2)
  ) sync_spi_off (
    .clk(aclk),
    .resetn(aresetn),
    .din(spi_off),
    .dout(spi_off_sync),
    .stable(spi_off_stable_flag)
  );

  // Integrator threshold status
  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_over_thresh (
    .clk(aclk),
    .resetn(aresetn),
    .din(over_thresh),
    .dout(over_thresh_sync),
    .stable(over_thresh_stable_flag)
  );
  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_thresh_underflow (
    .clk(aclk),
    .resetn(aresetn),
    .din(thresh_underflow),
    .dout(thresh_underflow_sync),
    .stable(thresh_underflow_stable_flag)
  );
  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_thresh_overflow (
    .clk(aclk),
    .resetn(aresetn),
    .din(thresh_overflow),
    .dout(thresh_overflow_sync),
    .stable(thresh_overflow_stable_flag)
  );

  // Trigger channel status
  synchronizer #(
    .DEPTH(3),
    .WIDTH(1),
    .STABLE_COUNT(2)
  ) sync_bad_trig_cmd (
    .clk(aclk),
    .resetn(aresetn),
    .din(bad_trig_cmd),
    .dout(bad_trig_cmd_sync),
    .stable(bad_trig_cmd_stable_flag)
  );
  synchronizer #(
    .DEPTH(3),
    .WIDTH(1),
    .STABLE_COUNT(2)
  ) sync_trig_data_buf_overflow (
    .clk(aclk),
    .resetn(aresetn),
    .din(trig_data_buf_overflow),
    .dout(trig_data_buf_overflow_sync),
    .stable(trig_data_buf_overflow_stable_flag)
  );

  // DAC channel status
  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_dac_boot_fail (
    .clk(aclk),
    .resetn(aresetn),
    .din(dac_boot_fail),
    .dout(dac_boot_fail_sync),
    .stable(dac_boot_fail_stable)
  );
  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_bad_dac_cmd (
    .clk(aclk),
    .resetn(aresetn),
    .din(bad_dac_cmd),
    .dout(bad_dac_cmd_sync),
    .stable(bad_dac_cmd_stable_flag)
  );
  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_dac_cal_oob (
    .clk(aclk),
    .resetn(aresetn),
    .din(dac_cal_oob),
    .dout(dac_cal_oob_sync),
    .stable(dac_cal_oob_stable_flag)
  );
  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_dac_val_oob (
    .clk(aclk),
    .resetn(aresetn),
    .din(dac_val_oob),
    .dout(dac_val_oob_sync),
    .stable(dac_val_oob_stable_flag)
  );
  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_dac_cmd_buf_underflow (
    .clk(aclk),
    .resetn(aresetn),
    .din(dac_cmd_buf_underflow),
    .dout(dac_cmd_buf_underflow_sync),
    .stable(dac_cmd_buf_underflow_stable_flag)
  );
  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_unexp_dac_trig (
    .clk(aclk),
    .resetn(aresetn),
    .din(unexp_dac_trig),
    .dout(unexp_dac_trig_sync),
    .stable(unexp_dac_trig_stable_flag)
  );

  // ADC channel status
  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_adc_boot_fail (
    .clk(aclk),
    .resetn(aresetn),
    .din(adc_boot_fail),
    .dout(adc_boot_fail_sync),
    .stable(adc_boot_fail_stable)
  );
  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_bad_adc_cmd (
    .clk(aclk),
    .resetn(aresetn),
    .din(bad_adc_cmd),
    .dout(bad_adc_cmd_sync),
    .stable(bad_adc_cmd_stable_flag)
  );
  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_adc_cmd_buf_underflow (
    .clk(aclk),
    .resetn(aresetn),
    .din(adc_cmd_buf_underflow),
    .dout(adc_cmd_buf_underflow_sync),
    .stable(adc_cmd_buf_underflow_stable_flag)
  );
  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_adc_data_buf_overflow (
    .clk(aclk),
    .resetn(aresetn),
    .din(adc_data_buf_overflow),
    .dout(adc_data_buf_overflow_sync),
    .stable(adc_data_buf_overflow_stable_flag)
  );
  synchronizer #(
    .DEPTH(3),
    .WIDTH(8),
    .STABLE_COUNT(2)
  ) sync_unexp_adc_trig (
    .clk(aclk),
    .resetn(aresetn),
    .din(unexp_adc_trig),
    .dout(unexp_adc_trig_sync),
    .stable(unexp_adc_trig_stable_flag)
  );

  //// Update stable registers for each signal individually
  always @(posedge aclk) begin
    // SPI system status
    spi_off_stable                <= spi_off_stable_flag                ? spi_off_sync                : 1'b0;
    // Integrator threshold status
    over_thresh_stable            <= over_thresh_stable_flag            ? over_thresh_sync            : 8'b0;
    thresh_underflow_stable       <= thresh_underflow_stable_flag       ? thresh_underflow_sync       : 8'b0;
    thresh_overflow_stable        <= thresh_overflow_stable_flag        ? thresh_overflow_sync        : 8'b0;
    // Trigger channel status
    bad_trig_cmd_stable           <= bad_trig_cmd_stable_flag           ? bad_trig_cmd_sync           : 1'b0;
    trig_data_buf_overflow_stable <= trig_data_buf_overflow_stable_flag ? trig_data_buf_overflow_sync : 1'b0;
    // DAC channel status
    dac_boot_fail_stable          <= dac_boot_fail_stable               ? dac_boot_fail_sync          : 8'b0;
    bad_adc_cmd_stable            <= bad_adc_cmd_stable_flag            ? bad_adc_cmd_sync            : 8'b0;
    bad_dac_cmd_stable            <= bad_dac_cmd_stable_flag            ? bad_dac_cmd_sync            : 8'b0;
    dac_cal_oob_stable            <= dac_cal_oob_stable_flag            ? dac_cal_oob_sync            : 8'b0;
    dac_val_oob_stable            <= dac_val_oob_stable_flag            ? dac_val_oob_sync            : 8'b0;
    dac_cmd_buf_underflow_stable  <= dac_cmd_buf_underflow_stable_flag  ? dac_cmd_buf_underflow_sync  : 8'b0;
    unexp_dac_trig_stable         <= unexp_dac_trig_stable_flag         ? unexp_dac_trig_sync         : 8'b0;
    // ADC channel status
    adc_boot_fail_stable          <= adc_boot_fail_stable               ? adc_boot_fail_sync          : 8'b0;
    bad_adc_cmd_stable            <= bad_adc_cmd_stable_flag            ? bad_adc_cmd_sync            : 8'b0;
    adc_cmd_buf_underflow_stable  <= adc_cmd_buf_underflow_stable_flag  ? adc_cmd_buf_underflow_sync  : 8'b0;
    adc_data_buf_overflow_stable  <= adc_data_buf_overflow_stable_flag  ? adc_data_buf_overflow_sync  : 8'b0;
    unexp_adc_trig_stable         <= unexp_adc_trig_stable_flag         ? unexp_adc_trig_sync         : 8'b0;
  end
endmodule
