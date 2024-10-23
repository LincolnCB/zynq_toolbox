`timescale 1 ns / 1 ps

// An AXIS wrapper around Xilinx's synchronous FIFO XPM_FIFO_SYNC. 
// This allows more features than the XPM_FIFO_AXIS, like forcing "always ready" or "always valid" behavior
//  which is preferred when directly interfacing with the PS (to prevent possible infinite hangs).
// Macro docs:
//  https://docs.amd.com/r/en-US/ug953-vivado-7series-libraries/XPM_FIFO_SYNC

// Parameters:
//  S_AXIS_TDATA_WIDTH: Width of the subordinate AXIS data bus
//  M_AXIS_TDATA_WIDTH: Width of the manager AXIS data bus  
//    Write and read width aspect ratio must be 1:1, 1:2, 1:4, 1:8, 8:1, 4:1, or 2:1 
//  WRITE_DEPTH: Depth of the FIFO (in subordinate words)
//    Must be a power of 2
//  ALWAYS_READY: If "TRUE" the ready signal is always high -- overflow is possible
//  ALWAYS_VALID: If "TRUE" the valid signal is always high -- underflow is possible
module axis_fifo_sync #
(
  parameter integer S_AXIS_TDATA_WIDTH = 32,
  parameter integer M_AXIS_TDATA_WIDTH = 32,
  parameter integer WRITE_DEPTH = 256,
  parameter         ALWAYS_READY = "FALSE",
  parameter         ALWAYS_VALID = "FALSE"
)
(
  // System signals
  input  wire                          aclk,
  input  wire                          aresetn,

  // FIFO status
  output wire [23:0]                   write_count,
  output wire [23:0]                   read_count,
  output wire                          empty,
  output wire                          full,
  output wire                          underflow,
  output wire                          overflow,

  // Subordinate AXIS
  input  wire [S_AXIS_TDATA_WIDTH-1:0] s_axis_tdata,
  input  wire                          s_axis_tvalid,
  output wire                          s_axis_tready,

  // Manager AXIS
  output wire [M_AXIS_TDATA_WIDTH-1:0] m_axis_tdata,
  output wire                          m_axis_tvalid,
  input  wire                          m_axis_tready
);

  // Width of the write and read count signals for for FIFO (in bits)
  localparam integer WRITE_COUNT_WIDTH = $clog2(WRITE_DEPTH) + 1;
  localparam integer READ_COUNT_WIDTH = $clog2(WRITE_DEPTH * S_AXIS_TDATA_WIDTH / M_AXIS_TDATA_WIDTH) + 1;

  // Internal wires
  wire [M_AXIS_TDATA_WIDTH-1:0] int_data_wire;

  // FIFO macro instantiation
  xpm_fifo_sync #(
    .WRITE_DATA_WIDTH(S_AXIS_TDATA_WIDTH),
    .FIFO_WRITE_DEPTH(WRITE_DEPTH),
    .READ_DATA_WIDTH(M_AXIS_TDATA_WIDTH),
    .READ_MODE("fwft"),
    .FIFO_READ_LATENCY(0),
    .FIFO_MEMORY_TYPE("block"),
    .USE_ADV_FEATURES("0505"), // Enable: overflow, underflow, write count, read count
    .WR_DATA_COUNT_WIDTH(WRITE_COUNT_WIDTH),
    .RD_DATA_COUNT_WIDTH(READ_COUNT_WIDTH)
  ) fifo_0 (
    .empty(empty),
    .full(full),
    .underflow(underflow),
    .overflow(overflow),
    .wr_data_count(write_count),
    .rd_data_count(read_count),
    .rst(~aresetn),
    .wr_clk(aclk),
    .wr_en(s_axis_tvalid),
    .din(s_axis_tdata),
    .rd_en(m_axis_tready),
    .dout(int_data_wire)
  );

  // Generate the ready signal according to behaviour choice
  generate
    if(ALWAYS_READY == "TRUE")
    begin : READY_INPUT
      assign s_axis_tready = 1'b1;
    end
    else
    begin : BLOCKING_INPUT
      assign s_axis_tready = ~full;
    end
  endgenerate

  // Generate the valid signal according to behaviour choice
  generate
    if(ALWAYS_VALID == "TRUE")
    begin : VALID_OUTPUT
      assign m_axis_tdata = empty ? {(M_AXIS_TDATA_WIDTH){1'b0}} : int_data_wire;
      assign m_axis_tvalid = 1'b1;
    end
    else
    begin : BLOCKING_OUTPUT
      assign m_axis_tdata = int_data_wire;
      assign m_axis_tvalid = ~empty;
    end
  endgenerate

endmodule
