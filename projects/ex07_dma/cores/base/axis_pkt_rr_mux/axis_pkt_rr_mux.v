`timescale 1 ns / 1 ps

// Round-robin AXI4-Stream packet mux: NUM_SI slave streams -> one master stream.
//
// Purpose in ex07: the S2MM side of the MCDMA has a single AXIS slave port that
// demultiplexes by TDEST, so the per-channel ADC FIFO streams must be merged
// onto one stream. MCDMA latches TDEST at start-of-packet and requires every
// beat of a packet to arrive contiguously; if beats from different channels
// interleave, the whole mix lands on the channel latched first and the rest
// starve. The stock axis_switch (ROUTING_MODE 0) could not be forced to
// arbitrate on packet boundaries (ARB_ON_TLAST does not stick on that IP), so
// this core replaces it with deterministic packet-atomic arbitration.
//
// Behaviour: grant one slave at a time and hold the grant for the whole packet
// (through the beat where TLAST is accepted), so packets never interleave on the
// master. TDATA/TDEST/TLAST pass through unchanged, so the downstream MCDMA S2MM
// routes each packet to the channel named by its TDEST. After a packet
// completes, arbitration advances round-robin to the next requesting slave, so
// no slave can be starved by a continuously-active neighbour.
//
// Fixed at NUM_SI = 4 slave interfaces (matches ex07 block_design.tcl num_ch = 4).
// The signal set (TDATA/TDEST/TLAST/TVALID/TREADY, no TKEEP) matches the
// axis_data_fifo M_AXIS that feeds it; MCDMA's TKEEP is tied off in the BD as it
// was for the direct loopback connection.
module axis_pkt_rr_mux #(
  parameter integer DATA_WIDTH = 32,
  parameter integer DEST_WIDTH = 8
)(
  input  wire                  aclk,
  input  wire                  aresetn,

  // Slave (input) stream 0
  input  wire [DATA_WIDTH-1:0] s00_axis_tdata,
  input  wire [DEST_WIDTH-1:0] s00_axis_tdest,
  input  wire                  s00_axis_tlast,
  input  wire                  s00_axis_tvalid,
  output wire                  s00_axis_tready,

  // Slave (input) stream 1
  input  wire [DATA_WIDTH-1:0] s01_axis_tdata,
  input  wire [DEST_WIDTH-1:0] s01_axis_tdest,
  input  wire                  s01_axis_tlast,
  input  wire                  s01_axis_tvalid,
  output wire                  s01_axis_tready,

  // Slave (input) stream 2
  input  wire [DATA_WIDTH-1:0] s02_axis_tdata,
  input  wire [DEST_WIDTH-1:0] s02_axis_tdest,
  input  wire                  s02_axis_tlast,
  input  wire                  s02_axis_tvalid,
  output wire                  s02_axis_tready,

  // Slave (input) stream 3
  input  wire [DATA_WIDTH-1:0] s03_axis_tdata,
  input  wire [DEST_WIDTH-1:0] s03_axis_tdest,
  input  wire                  s03_axis_tlast,
  input  wire                  s03_axis_tvalid,
  output wire                  s03_axis_tready,

  // Master (output) stream
  output wire [DATA_WIDTH-1:0] m_axis_tdata,
  output wire [DEST_WIDTH-1:0] m_axis_tdest,
  output wire                  m_axis_tlast,
  output wire                  m_axis_tvalid,
  input  wire                  m_axis_tready
);

  localparam integer NUM_SI = 4;

  initial begin
    if (DATA_WIDTH <= 0 || DATA_WIDTH % 8 != 0)
      $error("Invalid DATA_WIDTH parameter: %d. Must be > 0 and a multiple of 8.", DATA_WIDTH);
    if (DEST_WIDTH <= 0)
      $error("Invalid DEST_WIDTH parameter: %d. Must be > 0.", DEST_WIDTH);
  end

  // Pack the flat slave ports into arrays so the arbiter can index them.
  wire [DATA_WIDTH-1:0] s_tdata  [0:NUM_SI-1];
  wire [DEST_WIDTH-1:0] s_tdest  [0:NUM_SI-1];
  wire                  s_tlast  [0:NUM_SI-1];
  wire                  s_tvalid [0:NUM_SI-1];
  reg                   s_tready [0:NUM_SI-1];

  assign s_tdata[0]  = s00_axis_tdata;
  assign s_tdest[0]  = s00_axis_tdest;
  assign s_tlast[0]  = s00_axis_tlast;
  assign s_tvalid[0] = s00_axis_tvalid;
  assign s00_axis_tready = s_tready[0];

  assign s_tdata[1]  = s01_axis_tdata;
  assign s_tdest[1]  = s01_axis_tdest;
  assign s_tlast[1]  = s01_axis_tlast;
  assign s_tvalid[1] = s01_axis_tvalid;
  assign s01_axis_tready = s_tready[1];

  assign s_tdata[2]  = s02_axis_tdata;
  assign s_tdest[2]  = s02_axis_tdest;
  assign s_tlast[2]  = s02_axis_tlast;
  assign s_tvalid[2] = s02_axis_tvalid;
  assign s02_axis_tready = s_tready[2];

  assign s_tdata[3]  = s03_axis_tdata;
  assign s_tdest[3]  = s03_axis_tdest;
  assign s_tlast[3]  = s03_axis_tlast;
  assign s_tvalid[3] = s03_axis_tvalid;
  assign s03_axis_tready = s_tready[3];

  // Arbiter state.
  reg              busy;    // a packet is currently being forwarded
  reg  [1:0]       grant;   // which slave holds the grant while busy
  reg  [1:0]       rr_ptr;  // round-robin search origin for the next packet

  // Round-robin next-grant search: scan NUM_SI slaves starting at rr_ptr and
  // pick the first that is asserting TVALID. The 2-bit index wraps mod 4.
  integer          k;
  reg  [1:0]        cand;
  reg               found;
  reg  [1:0]        next_grant;
  always @* begin
    found      = 1'b0;
    next_grant = rr_ptr;
    for (k = 0; k < NUM_SI; k = k + 1) begin
      cand = rr_ptr + k[1:0];
      if (!found && s_tvalid[cand]) begin
        next_grant = cand;
        found       = 1'b1;
      end
    end
  end

  wire last_beat = m_axis_tvalid && m_axis_tready && m_axis_tlast;

  always @(posedge aclk) begin
    if (!aresetn) begin
      busy   <= 1'b0;
      grant  <= 2'd0;
      rr_ptr <= 2'd0;
    end else if (!busy) begin
      if (found) begin
        grant <= next_grant;
        busy  <= 1'b1;
      end
    end else if (last_beat) begin
      busy   <= 1'b0;
      rr_ptr <= grant + 2'd1;   // resume the search past the served slave
    end
  end

  // Route TREADY only to the granted slave.
  integer j;
  always @* begin
    for (j = 0; j < NUM_SI; j = j + 1)
      s_tready[j] = 1'b0;
    if (busy)
      s_tready[grant] = m_axis_tready;
  end

  // Master stream is the granted slave, gated by busy.
  assign m_axis_tvalid = busy ? s_tvalid[grant] : 1'b0;
  assign m_axis_tdata  = s_tdata[grant];
  assign m_axis_tdest  = s_tdest[grant];
  assign m_axis_tlast  = s_tlast[grant];

endmodule
