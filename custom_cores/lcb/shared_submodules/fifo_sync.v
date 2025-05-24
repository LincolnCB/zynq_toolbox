module fifo_sync #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 4,  // FIFO depth = 2^ADDR_WIDTH
    parameter ALMOST_FULL_THRESHOLD = 2, // Adjust as needed
    parameter ALMOST_EMPTY_THRESHOLD = 2 // Adjust as needed
)(
    input  wire                   clk,
    input  wire                   aresetn,
    input  wire [DATA_WIDTH-1:0]  wr_data,
    input  wire                   wr_en,
    output wire                   full,
    output wire                   almost_full,

    output reg  [DATA_WIDTH-1:0]  rd_data,
    input  wire                   rd_en,
    output wire                   empty,
    output wire                   almost_empty
);

    // FIFO memory
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    // Write and read pointers
    reg [ADDR_WIDTH:0] wr_ptr_bin;
    reg [ADDR_WIDTH:0] rd_ptr_bin;

    // Write logic
    always @(posedge clk) begin
        if (~aresetn) begin
            wr_ptr_bin <= 0;
        end else if (wr_en && !full) begin
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
            wr_ptr_bin <= wr_ptr_bin + 1;
        end
    end

    // Read logic
    always @(posedge clk) begin
        if (~aresetn) begin
            rd_ptr_bin <= 0;
        end else if (rd_en && !empty) begin
            rd_data <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
            rd_ptr_bin <= rd_ptr_bin + 1;
        end
    end

    // Generate full and empty flags
    assign full  = ( (wr_ptr_bin[ADDR_WIDTH] != rd_ptr_bin[ADDR_WIDTH]) &&
                     (wr_ptr_bin[ADDR_WIDTH-1:0] == rd_ptr_bin[ADDR_WIDTH-1:0]) );
    assign empty = (wr_ptr_bin == rd_ptr_bin);

    // FIFO count
    wire [ADDR_WIDTH:0] fifo_count;
    assign fifo_count = wr_ptr_bin - rd_ptr_bin;

    // Almost full/empty
    assign almost_full  = (fifo_count >= ((1 << ADDR_WIDTH) - ALMOST_FULL_THRESHOLD));
    assign almost_empty = (fifo_count <= ALMOST_EMPTY_THRESHOLD);

endmodule
