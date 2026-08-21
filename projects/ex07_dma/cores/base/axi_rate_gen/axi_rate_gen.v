`timescale 1 ns / 1 ps

// Per-channel AXI4-Stream rate limiter for ex07's DAC->ADC datapath.
//
// Sits between a channel's DAC FIFO (M_AXIS) and ADC FIFO (S_AXIS), where the
// SPI core lives in rev_d_shim. It forwards beats unchanged (tdata/tdest/tlast
// preserved so TDEST routing and packet boundaries survive) but throttles the
// stream to a programmed rate and can pause it, standing in for the SPI core's
// pacing. A full downstream FIFO still backpressures through it normally.
//
// Control (`cfg`) and status (`sts`) are one 32-bit word per channel, driven by
// slices of a shared axi_cfg_register / axi_sts_register in the block design and
// reachable non-root via pl-reg (see ex05). Register layout:
//   cfg[RATE_WIDTH-1:0] RATE_DIV  extra idle cycles between forwarded beats
//                                 (0 = full rate, N = one beat every N+1 cycles)
//   cfg[16]             PAUSE     freeze forwarding while set
//   sts[31:0]           BEAT_COUNT saturating count of beats forwarded since reset
module axi_rate_gen #(
  parameter integer DATA_WIDTH = 32,
  parameter integer DEST_WIDTH = 8,
  parameter integer RATE_WIDTH = 16
)(
  input  wire                   aclk,
  input  wire                   aresetn,

  // Per-channel control / status (slice of the shared cfg/sts register)
  input  wire [31:0]            cfg,
  output wire [31:0]            sts,

  // AXI4-Stream slave (from the DAC FIFO)
  input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
  input  wire [DEST_WIDTH-1:0]  s_axis_tdest,
  input  wire                   s_axis_tlast,
  input  wire                   s_axis_tvalid,
  output wire                   s_axis_tready,

  // AXI4-Stream master (to the ADC FIFO)
  output wire [DATA_WIDTH-1:0]  m_axis_tdata,
  output wire [DEST_WIDTH-1:0]  m_axis_tdest,
  output wire                   m_axis_tlast,
  output wire                   m_axis_tvalid,
  input  wire                   m_axis_tready
);

  // Validate parameters
  initial begin
    if (DATA_WIDTH <= 0 || DATA_WIDTH % 8 != 0)
      $error("Invalid DATA_WIDTH parameter: %d. Must be > 0 and a multiple of 8.", DATA_WIDTH);
    if (DEST_WIDTH <= 0)
      $error("Invalid DEST_WIDTH parameter: %d. Must be greater than 0.", DEST_WIDTH);
    if (RATE_WIDTH <= 0 || RATE_WIDTH > 32)
      $error("Invalid RATE_WIDTH parameter: %d. Must be between 1 and 32.", RATE_WIDTH);
  end

  wire [RATE_WIDTH-1:0] rate_div = cfg[RATE_WIDTH-1:0];
  wire                  pause    = cfg[16];

  // Rate token: a beat may pass only when the cooldown has elapsed and not paused.
  reg  [RATE_WIDTH-1:0] wait_cnt;
  wire                  token = (wait_cnt == {RATE_WIDTH{1'b0}}) && !pause;

  // Gated, storeless passthrough of the stream payload.
  assign m_axis_tdata  = s_axis_tdata;
  assign m_axis_tdest  = s_axis_tdest;
  assign m_axis_tlast  = s_axis_tlast;
  assign m_axis_tvalid = s_axis_tvalid && token;
  assign s_axis_tready = m_axis_tready && token;

  wire beat = m_axis_tvalid && m_axis_tready;

  reg [31:0] beat_count;
  assign sts = beat_count;

  always @(posedge aclk) begin
    if (!aresetn) begin
      wait_cnt   <= {RATE_WIDTH{1'b0}};
      beat_count <= 32'd0;
    end else begin
      if (beat) begin
        wait_cnt <= rate_div;                        // reload cooldown after a beat
        if (beat_count != 32'hFFFFFFFF)
          beat_count <= beat_count + 32'd1;          // saturating
      end else if (wait_cnt != {RATE_WIDTH{1'b0}}) begin
        wait_cnt <= wait_cnt - {{(RATE_WIDTH-1){1'b0}}, 1'b1};
      end
    end
  end

endmodule
