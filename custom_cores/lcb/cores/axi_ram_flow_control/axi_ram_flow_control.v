`timescale 1 ns / 1 ps

module axi_ram_flow_control #
(
  parameter integer ADDR_WIDTH = 16,
  parameter integer AXI_ID_WIDTH = 6,
  parameter integer AXI_ADDR_WIDTH = 32,
  parameter integer AXI_DATA_WIDTH = 64,
  parameter integer AXIS_TDATA_WIDTH = 64,
  parameter integer FIFO_WRITE_DEPTH = 512
)
(
  // System signals
  input  wire                        aclk,
  input  wire                        aresetn,

  input  wire                        dma_enable,

  // Configuration and status
  input  wire [AXI_ADDR_WIDTH-1:0]   min_addr_writer,
  input  wire [AXI_ADDR_WIDTH-1:0]   min_addr_reader,
  input  wire [ADDR_WIDTH-1:0]       sample_count_writer,
  input  wire [ADDR_WIDTH-1:0]       sample_count_reader,

  // Start/End pointers
  input  wire [ADDR_WIDTH-1:0]       writer_start_ptr,
  output wire [ADDR_WIDTH-1:0]       writer_end_ptr,
  output wire [ADDR_WIDTH-1:0]       reader_start_ptr,
  input  wire [ADDR_WIDTH-1:0]       reader_end_ptr,

  // Status signals
  output wire                        overflow_out,
  output wire                        underflow_out,
  output wire                        overflow_in,
  output wire                        underflow_in,

  // AXI Master Write Interface
  output wire [AXI_ID_WIDTH-1:0]     m_axi_awid,
  output wire [3:0]                  m_axi_awlen,
  output wire [2:0]                  m_axi_awsize,
  output wire [1:0]                  m_axi_awburst,
  output wire [3:0]                  m_axi_awcache,
  output wire [AXI_ADDR_WIDTH-1:0]   m_axi_awaddr,
  output wire                        m_axi_awvalid,
  input  wire                        m_axi_awready,

  output wire [AXI_ID_WIDTH-1:0]     m_axi_wid,
  output wire [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
  output wire                        m_axi_wlast,
  output wire [AXI_DATA_WIDTH-1:0]   m_axi_wdata,
  output wire                        m_axi_wvalid,
  input  wire                        m_axi_wready,

  input  wire                        m_axi_bvalid,
  output wire                        m_axi_bready,

  // AXI Master Read Interface
  output wire [AXI_ID_WIDTH-1:0]     m_axi_arid,
  output wire [3:0]                  m_axi_arlen,
  output wire [2:0]                  m_axi_arsize,
  output wire [1:0]                  m_axi_arburst,
  output wire [3:0]                  m_axi_arcache,
  output wire [AXI_ADDR_WIDTH-1:0]   m_axi_araddr,
  output wire                        m_axi_arvalid,
  input  wire                        m_axi_arready,

  input  wire [AXI_ID_WIDTH-1:0]     m_axi_rid,
  input  wire                        m_axi_rlast,
  input  wire [AXI_DATA_WIDTH-1:0]   m_axi_rdata,
  input  wire                        m_axi_rvalid,
  output wire                        m_axi_rready,

  // AXIS Slave Write Interface
  input  wire [AXIS_TDATA_WIDTH-1:0] s_axis_tdata,
  input  wire                        s_axis_tvalid,
  output wire                        s_axis_tready,

  // AXIS Master Read Interface
  output wire [AXIS_TDATA_WIDTH-1:0] m_axis_tdata,
  output wire                        m_axis_tvalid,
  input  wire                        m_axis_tready
);

  localparam integer FIFO_READ_DEPTH = FIFO_WRITE_DEPTH * AXIS_TDATA_WIDTH / AXI_DATA_WIDTH;

  reg stopped;

  reg writer_enable;
  reg reader_enable;
  
  wire writer_start_loop_parity;
  wire writer_end_loop_parity;
  wire reader_start_loop_parity;
  wire reader_end_loop_parity;
  reg  prev_writer_start_loop_parity;
  reg  prev_writer_end_loop_parity;
  reg  prev_reader_start_loop_parity;
  reg  prev_reader_end_loop_parity;

  reg [ADDR_WIDTH-1:0] prev_writer_start_ptr;
  reg [ADDR_WIDTH-1:0] prev_writer_end_ptr;
  reg [ADDR_WIDTH-1:0] prev_reader_start_ptr;
  reg [ADDR_WIDTH-1:0] prev_reader_end_ptr;

  // Instantiate the AXI RAM Writer
  axis_ram_writer #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXIS_TDATA_WIDTH(AXIS_TDATA_WIDTH),
    .FIFO_WRITE_DEPTH(FIFO_WRITE_DEPTH)
  ) writer_inst (
    .aclk(aclk),
    .aresetn(aresetn),
    .min_addr(min_addr_writer),
    .cfg_data(sample_count_writer),
    .sts_data(writer_end_ptr),
    .m_axi_awid(m_axi_awid),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awcache(m_axi_awcache),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_wid(m_axi_wid),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready)
  );

  // Instantiate the AXI RAM Reader
  axis_ram_reader #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXIS_TDATA_WIDTH(AXIS_TDATA_WIDTH),
    .FIFO_WRITE_DEPTH(FIFO_READ_DEPTH)
  ) reader_inst (
    .aclk(aclk),
    .aresetn(aresetn),
    .min_addr(min_addr_reader),
    .cfg_data(sample_count_reader),
    .sts_data(reader_start_ptr),
    .m_axi_arid(m_axi_arid),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arcache(m_axi_arcache),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rid(m_axi_rid),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready)
  );

  // Loop detection logic
  assign writer_start_loop_parity = (writer_start_ptr < prev_writer_start_ptr) ? ~prev_writer_start_loop_parity : prev_writer_start_loop_parity;
  assign writer_end_loop_parity = (writer_end_ptr < prev_writer_end_ptr) ? ~prev_writer_end_loop_parity : prev_writer_end_loop_parity;
  assign reader_start_loop_parity = (reader_start_ptr < prev_reader_start_ptr) ? ~prev_reader_start_loop_parity : prev_reader_start_loop_parity;
  assign reader_end_loop_parity = (reader_end_ptr < prev_reader_end_ptr) ? ~prev_reader_end_loop_parity : prev_reader_end_loop_parity;

  // Control logic for flow control
  always @(posedge aclk or negedge aresetn) begin
    if (~aresetn) begin
      prev_writer_start_loop_parity <= 1'b0;
      prev_writer_end_loop_parity <= 1'b0;
      prev_reader_start_loop_parity <= 1'b0;
      prev_reader_end_loop_parity <= 1'b0;
      prev_writer_start_ptr <= 0;
      prev_writer_end_ptr <= 0;
      prev_reader_start_ptr <= 0;
      prev_reader_end_ptr <= 0;
      writer_enable <= 1'b0;
      reader_enable <= 1'b0;
      stopped <= 1'b0;
      overflow_out <= 1'b0;
      underflow_out <= 1'b0;
      overflow_in <= 1'b0;
      underflow_in <= 1'b0;
    end else if (dma_enable & ~stopped) begin
      // Update previous pointers
      prev_writer_start_loop_parity <= writer_start_loop_parity;
      prev_writer_end_loop_parity <= writer_end_loop_parity;
      prev_reader_start_loop_parity <= reader_start_loop_parity;
      prev_reader_end_loop_parity <= reader_end_loop_parity;
      prev_writer_start_ptr <= writer_start_ptr;
      prev_writer_end_ptr <= writer_end_ptr;
      prev_reader_start_ptr <= reader_start_ptr;
      prev_reader_end_ptr <= reader_end_ptr;

      // Check for wrap-around violation
      if (writer_start_loop_parity == writer_end_loop_parity) begin
        if (writer_start_ptr > writer_end_ptr) begin
          underflow_out <= 1'b1;
          stopped <= 1'b1;
        end
      end else begin
        if (writer_start_ptr < writer_end_ptr) begin
          overflow_out <= 1'b1;
          stopped <= 1'b1;
        end
      end
      if (reader_start_loop_parity == reader_end_loop_parity) begin
        if (reader_start_ptr > reader_end_ptr) begin
          underflow_in <= 1'b1;
          stopped <= 1'b1;
        end
      end else begin
        if (reader_start_ptr < reader_end_ptr) begin
          overflow_in <= 1'b1;
          stopped <= 1'b1;
        end
      end

      // Enable writer if there's space (track loop parity to account for wrap-around)
      writer_enable <= (writer_start_loop_parity == writer_end_loop_parity) ? 1'b1
                    : (writer_start_ptr > writer_end_ptr) ? 1'b1
                    : 1'b0;
      // Enable reader if there's space
      reader_enable <= (reader_start_loop_parity != reader_end_loop_parity) ? 1'b1
                    : (reader_start_ptr < reader_end_ptr) ? 1'b1
                    : 1'b0;
    end
  end
endmodule
