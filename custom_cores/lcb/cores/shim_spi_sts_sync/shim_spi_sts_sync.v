`timescale 1ns/1ps

module shim_spi_sts_sync (
  input  wire        aclk,       // AXI domain clock
  input  wire        aresetn,    // Active low reset signal
  input  wire        spi_clk,    // SPI domain clock
  input  wire        spi_resetn, // Active low reset signal for SPI domain
  
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
  output wire        spi_off_sync,
  // Integrator threshold status
  output wire [7:0]  over_thresh_sync,
  output wire [7:0]  thresh_underflow_sync,
  output wire [7:0]  thresh_overflow_sync,
  // Trigger channel status
  output wire        bad_trig_cmd_sync,
  output wire        trig_data_buf_overflow_sync,
  // DAC channel status
  output wire [7:0]  dac_boot_fail_sync,
  output wire [7:0]  bad_dac_cmd_sync,
  output wire [7:0]  dac_cal_oob_sync,
  output wire [7:0]  dac_val_oob_sync,
  output wire [7:0]  dac_cmd_buf_underflow_sync,
  output wire [7:0]  unexp_dac_trig_sync,
  // ADC channel status
  output wire [7:0]  adc_boot_fail_sync,
  output wire [7:0]  bad_adc_cmd_sync,
  output wire [7:0]  adc_cmd_buf_underflow_sync,
  output wire [7:0]  adc_data_buf_overflow_sync,
  output wire [7:0]  unexp_adc_trig_sync
);

  // Default values for registers
  localparam spi_off_default = 1'b0;
  localparam [7:0] over_thresh_default = 8'b0;
  localparam [7:0] thresh_underflow_default = 8'b0;
  localparam [7:0] thresh_overflow_default = 8'b0;
  localparam [7:0] bad_trig_cmd_default = 1'b0;
  localparam [7:0] trig_data_buf_overflow_default = 1'b0;
  localparam [7:0] dac_boot_fail_default = 8'b0;
  localparam [7:0] bad_dac_cmd_default = 8'b0;
  localparam [7:0] dac_cal_oob_default = 8'b0;
  localparam [7:0] dac_val_oob_default = 8'b0;
  localparam [7:0] dac_cmd_buf_underflow_default = 8'b0;
  localparam [7:0] unexp_dac_trig_default = 8'b0;
  localparam [7:0] adc_boot_fail_default = 8'b0;
  localparam [7:0] bad_adc_cmd_default = 8'b0;
  localparam [7:0] adc_cmd_buf_underflow_default = 8'b0;
  localparam [7:0] adc_data_buf_overflow_default = 8'b0;
  localparam [7:0] unexp_adc_trig_default = 8'b0;

  //// Synchronize each signal using a sync_coherent module
  // SPI system on/off status
  sync_coherent #(
    .WIDTH(1)
  ) sync_spi_off (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(spi_off),
    .dout(spi_off_sync),
    .dout_default(spi_off_default)
  );

  // Integrator threshold status
  sync_coherent #(
    .WIDTH(8)
  ) sync_over_thresh (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(over_thresh),
    .dout(over_thresh_sync),
    .dout_default(over_thresh_default)
  );
  sync_coherent #(
    .WIDTH(8)
  ) sync_thresh_underflow (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(thresh_underflow),
    .dout(thresh_underflow_sync),
    .dout_default(thresh_underflow_default)
  );
  sync_coherent #(
    .WIDTH(8)
  ) sync_thresh_overflow (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(thresh_overflow),
    .dout(thresh_overflow_sync),
    .dout_default(thresh_overflow_default)
  );

  // Trigger channel status
  sync_coherent #(
    .WIDTH(1)
  ) sync_bad_trig_cmd (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(bad_trig_cmd),
    .dout(bad_trig_cmd_sync),
    .dout_default(bad_trig_cmd_default)
  );
  sync_coherent #(
    .WIDTH(1)
  ) sync_trig_data_buf_overflow (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(trig_data_buf_overflow),
    .dout(trig_data_buf_overflow_sync),
    .dout_default(trig_data_buf_overflow_default)
  );

  // DAC channel status
  sync_coherent #(
    .WIDTH(8)
  ) sync_dac_boot_fail (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(dac_boot_fail),
    .dout(dac_boot_fail_sync),
    .dout_default(dac_boot_fail_default)
  );
  sync_coherent #(
    .WIDTH(8)
  ) sync_bad_dac_cmd (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(bad_dac_cmd),
    .dout(bad_dac_cmd_sync),
    .dout_default(bad_dac_cmd_default)
  );
  sync_coherent #(
    .WIDTH(8)
  ) sync_dac_cal_oob (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(dac_cal_oob),
    .dout(dac_cal_oob_sync),
    .dout_default(dac_cal_oob_default)
  );
  sync_coherent #(
    .WIDTH(8)
  ) sync_dac_val_oob (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(dac_val_oob),
    .dout(dac_val_oob_sync),
    .dout_default(dac_val_oob_default)
  );
  sync_coherent #(
    .WIDTH(8)
  ) sync_dac_cmd_buf_underflow (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(dac_cmd_buf_underflow),
    .dout(dac_cmd_buf_underflow_sync),
    .dout_default(dac_cmd_buf_underflow_default)
  );
  sync_coherent #(
    .WIDTH(8)
  ) sync_unexp_dac_trig (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(unexp_dac_trig),
    .dout(unexp_dac_trig_sync),
    .dout_default(unexp_dac_trig_default)
  );

  // ADC channel status
  sync_coherent #(
    .WIDTH(8)
  ) sync_adc_boot_fail (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(adc_boot_fail),
    .dout(adc_boot_fail_sync),
    .dout_default(adc_boot_fail_default)
  );
  sync_coherent #(
    .WIDTH(8)
  ) sync_bad_adc_cmd (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(bad_adc_cmd),
    .dout(bad_adc_cmd_sync),
    .dout_default(bad_adc_cmd_default)
  );
  sync_coherent #(
    .WIDTH(8)
  ) sync_adc_cmd_buf_underflow (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(adc_cmd_buf_underflow),
    .dout(adc_cmd_buf_underflow_sync),
    .dout_default(adc_cmd_buf_underflow_default)
  );
  sync_coherent #(
    .WIDTH(8)
  ) sync_adc_data_buf_overflow (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(adc_data_buf_overflow),
    .dout(adc_data_buf_overflow_sync),
    .dout_default(adc_data_buf_overflow_default)
  );
  sync_coherent #(
    .WIDTH(8)
  ) sync_unexp_adc_trig (
    .in_clk(spi_clk),
    .in_resetn(spi_resetn),
    .out_clk(aclk),
    .out_resetn(aresetn),
    .din(unexp_adc_trig),
    .dout(unexp_adc_trig_sync),
    .dout_default(unexp_adc_trig_default)
  );

endmodule
