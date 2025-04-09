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

  // Configuration and status
  input  wire [AXI_ADDR_WIDTH-1:0]   min_addr_writer,
  input  wire [AXI_ADDR_WIDTH-1:0]   min_addr_reader,
  input  wire [ADDR_WIDTH-1:0]       sample_count_cfg_writer,
  input  wire [ADDR_WIDTH-1:0]       sample_count_cfg_reader,
  output wire [ADDR_WIDTH-1:0]       sample_count_sts_writer,
  output wire [ADDR_WIDTH-1:0]       sample_count_sts_reader,

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
    .sample_count_cfg(sample_count_cfg_writer),
    .sample_count_sts(sample_count_sts_writer),
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
    .FIFO_WRITE_DEPTH(FIFO_WRITE_DEPTH)
  ) reader_inst (
    .aclk(aclk),
    .aresetn(aresetn),
    .min_addr(min_addr_reader),
    .sample_count_cfg(sample_count_cfg_reader),
    .sample_count_sts(sample_count_sts_reader),
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

endmodule
