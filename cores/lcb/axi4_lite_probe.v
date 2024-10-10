`timescale 1 ns / 1 ps

module axi4_lite_probe
(
  // AXI4-Lite Interface
  input  wire                      aclk,
  input  wire                      aresetn,

  // AXI4-Lite Subordinate side -- connect to the AXI4-Lite Manager
  input  wire [11:0]               s_axi_awid,
  input  wire [31:0]               s_axi_awaddr,
  input  wire                      s_axi_awvalid,
  output wire                      s_axi_awready,

  input  wire [3:0]                s_axi_wstrb,
  input  wire                      s_axi_wlast,
  input  wire [31:0]               s_axi_wdata,
  input  wire                      s_axi_wvalid,
  output wire                      s_axi_wready,

  output wire [11:0]               s_axi_bid,
  output wire                      s_axi_bvalid,
  input  wire                      s_axi_bready,

  input  wire [11:0]               s_axi_arid,
  input  wire [3:0]                s_axi_arlen,
  input  wire [31:0]               s_axi_araddr,
  input  wire                      s_axi_arvalid,
  output wire                      s_axi_arready,

  output wire [11:0]               s_axi_rid,
  output wire                      s_axi_rlast,
  output wire [31:0]               s_axi_rdata,
  output wire                      s_axi_rvalid,
  input  wire                      s_axi_rready,

  // AXI4-Lite Master side -- connect to the AXI4-Lite Slave
  output wire [11:0]               m_axi_awid,
  output wire [31:0]               m_axi_awaddr,
  output wire                      m_axi_awvalid,
  input  wire                      m_axi_awready,
  
  output wire [3:0]                m_axi_wstrb,
  output wire                      m_axi_wlast,
  output wire [31:0]               m_axi_wdata,
  output wire                      m_axi_wvalid,
  input  wire                      m_axi_wready,

  input  wire [11:0]               m_axi_bid,
  input  wire                      m_axi_bvalid,
  output wire                      m_axi_bready,

  output wire [11:0]               m_axi_arid,
  output wire [3:0]                m_axi_arlen,
  output wire [31:0]               m_axi_araddr,
  output wire                      m_axi_arvalid,
  input  wire                      m_axi_arready,

  input  wire [11:0]               m_axi_rid,
  input  wire                      m_axi_rlast,
  input  wire [31:0]               m_axi_rdata,
  input  wire                      m_axi_rvalid,
  output wire                      m_axi_rready

  // Probe side -- Outputs of all the AXI4-Lite signals
  output wire [11:0]               p_axi_awid,
  output wire [31:0]               p_axi_awaddr,
  output wire                      p_axi_awvalid,
  output wire                      p_axi_awready,

  output wire [3:0]                p_axi_wstrb,
  output wire                      p_axi_wlast,
  output wire [31:0]               p_axi_wdata,
  output wire                      p_axi_wvalid,
  output wire                      p_axi_wready,

  output wire [11:0]               p_axi_bid,
  output wire                      p_axi_bvalid,
  output wire                      p_axi_bready,

  output wire [11:0]               p_axi_arid,
  output wire [3:0]                p_axi_arlen,
  output wire [31:0]               p_axi_araddr,
  output wire                      p_axi_arvalid,
  output wire                      p_axi_arready,

  output wire [11:0]               p_axi_rid,
  output wire                      p_axi_rlast,
  output wire [31:0]               p_axi_rdata,
  output wire                      p_axi_rvalid,
  output wire                      p_axi_rready
);

  // Connect the AXI4-Lite interface through the system
  assign m_axi_awid = s_axi_awid;
  assign m_axi_awaddr = s_axi_awaddr;
  assign m_axi_awvalid = s_axi_awvalid;
  assign s_axi_awready = m_axi_awready;

  assign m_axi_wstrb = s_axi_wstrb;
  assign m_axi_wlast = s_axi_wlast;
  assign m_axi_wdata = s_axi_wdata;
  assign m_axi_wvalid = s_axi_wvalid;
  assign s_axi_wready = m_axi_wready;

  assign s_axi_bid = m_axi_bid;
  assign s_axi_bvalid = m_axi_bvalid;
  assign m_axi_bready = s_axi_bready;

  assign m_axi_arid = s_axi_arid;
  assign m_axi_arlen = s_axi_arlen;
  assign m_axi_araddr = s_axi_araddr;
  assign m_axi_arvalid = s_axi_arvalid;
  assign s_axi_arready = m_axi_arready;

  assign s_axi_rid = m_axi_rid;
  assign s_axi_rlast = m_axi_rlast;
  assign s_axi_rdata = m_axi_rdata;
  assign s_axi_rvalid = m_axi_rvalid;
  assign m_axi_rready = s_axi_rready;

  // Connect the Probe to all the inputs

  assign p_axi_awid = s_axi_awid;
  assign p_axi_awaddr = s_axi_awaddr;
  assign p_axi_awvalid = s_axi_awvalid;
  assign p_axi_awready = m_axi_awready;

  assign p_axi_wstrb = s_axi_wstrb;
  assign p_axi_wlast = s_axi_wlast;
  assign p_axi_wdata = s_axi_wdata;
  assign p_axi_wvalid = s_axi_wvalid;
  assign p_axi_wready = m_axi_wready;

  assign p_axi_bid = m_axi_bid;
  assign p_axi_bvalid = m_axi_bvalid;
  assign p_axi_bready = s_axi_bready;

  assign p_axi_arid = s_axi_arid;
  assign p_axi_arlen = s_axi_arlen;
  assign p_axi_araddr = s_axi_araddr;
  assign p_axi_arvalid = s_axi_arvalid;
  assign p_axi_arready = m_axi_arready;

  assign p_axi_rid = m_axi_rid;
  assign p_axi_rlast = m_axi_rlast;
  assign p_axi_rdata = m_axi_rdata;
  assign p_axi_rvalid = m_axi_rvalid;
  assign p_axi_rready = s_axi_rready;

endmodule
