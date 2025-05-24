`timescale 1 ns / 1 ps

module axi_fifo_bridge #(
    parameter integer AXI_ADDR_WIDTH = 8,
    parameter integer AXI_DATA_WIDTH = 32,
    parameter integer FIFO_DEPTH     = 16,
    parameter         ENABLE_WRITE   = 1, // 1=enable AXI writes to FIFO
    parameter         ENABLE_READ    = 1  // 1=enable AXI reads from FIFO
)(
    input  wire                       aclk,
    input  wire                       aresetn,

    // AXI4-Lite subordinate interface
    input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire                       s_axi_awvalid,
    output wire                       s_axi_awready,
    input  wire [AXI_DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [3:0]                 s_axi_wstrb,
    input  wire                       s_axi_wvalid,
    output wire                       s_axi_wready,
    output reg  [1:0]                 s_axi_bresp,
    output reg                        s_axi_bvalid,
    input  wire                       s_axi_bready,
    input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire                       s_axi_arvalid,
    output wire                       s_axi_arready,
    output reg  [AXI_DATA_WIDTH-1:0]  s_axi_rdata,
    output reg  [1:0]                 s_axi_rresp,
    output reg                        s_axi_rvalid,
    input  wire                       s_axi_rready,

    // FIFO write side
    output wire [AXI_DATA_WIDTH-1:0]  fifo_wr_data,
    output wire                       fifo_wr_en,
    input  wire                       fifo_full,
    input  wire                       fifo_almost_full,

    // FIFO read side
    input  wire [AXI_DATA_WIDTH-1:0]  fifo_rd_data,
    output wire                       fifo_rd_en,
    input  wire                       fifo_empty,
    input  wire                       fifo_almost_empty
);

    // Write logic
    wire write_addr_phase = s_axi_awvalid && s_axi_wvalid && ENABLE_WRITE;
    assign s_axi_awready = !fifo_full && ENABLE_WRITE;
    assign s_axi_wready  = !fifo_full && ENABLE_WRITE;
    assign fifo_wr_en    = write_addr_phase && !fifo_full && ENABLE_WRITE;
    assign fifo_wr_data  = s_axi_wdata;

    // Write response
    always @(posedge aclk) begin
        if (~aresetn) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00;
        end else begin
            if (fifo_wr_en) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00; // OKAY
            end else if (write_addr_phase && (!ENABLE_WRITE || fifo_full)) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b10; // SLVERR
            end else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // Read logic
    assign s_axi_arready = !fifo_empty && ENABLE_READ;
    assign fifo_rd_en    = s_axi_arvalid && s_axi_arready && ENABLE_READ;

    always @(posedge aclk) begin
        if (~aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rresp  <= 2'b00;
            s_axi_rdata  <= {AXI_DATA_WIDTH{1'b0}};
        end else begin
            if (fifo_rd_en) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00; // OKAY
                s_axi_rdata  <= fifo_rd_data;
            end else if (s_axi_arvalid && (!ENABLE_READ || fifo_empty)) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b10; // SLVERR
                s_axi_rdata  <= {AXI_DATA_WIDTH{1'b0}};
            end else if (s_axi_rready && s_axi_rvalid) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
