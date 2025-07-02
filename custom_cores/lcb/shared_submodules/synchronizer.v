`timescale 1ps/1ps

module synchronizer #(
  parameter DEPTH = 2,  // Depth of the synchronizer
  parameter WIDTH = 1,   // Width of the input and output signals
  parameter STABLE_COUNT = 2 // Stability count for the stable output signal
)(
  input  wire clk,               // Clock signal
  input  wire resetn,            // Active low reset signal
  input  wire [WIDTH-1:0] din,   // Input signal to be synchronized
  output wire [WIDTH-1:0] dout,  // Synchronized output signal
  output reg  stable // Indicates if the output signal is stable for the specified count
);

  // Ensure DEPTH is at least 2
  localparam MIN_DEPTH = 2;
  localparam SYNC_DEPTH = (DEPTH < MIN_DEPTH) ? MIN_DEPTH : DEPTH;

  // Ensure stability count is at least 1
  localparam MIN_STABLE_COUNT = 1;
  localparam NONZ_STABLE_COUNT = (STABLE_COUNT < MIN_STABLE_COUNT) ? MIN_STABLE_COUNT : STABLE_COUNT;

  // Previous dout value for comparison
  reg [WIDTH-1:0] prev_dout;

  function integer clogb2 (input integer value);
    for(clogb2 = 0; value > 0; clogb2 = clogb2 + 1) value = value >> 1;
  endfunction

  // Internal flip-flop chain
  reg [WIDTH-1:0] sync_chain [SYNC_DEPTH-1:0];
  // Stable signal
  reg [clogb2(NONZ_STABLE_COUNT+1)-1:0] stable_counter;

  // Initial stage logic
  always @(posedge clk) begin
    if (!resetn) begin
      sync_chain[0] <= {WIDTH{1'b0}};
    end else begin
      sync_chain[0] <= din;
    end
  end

  // Generate the synchronizer chain
  genvar i;
  generate
    for (i = 1; i < SYNC_DEPTH; i = i + 1) begin : sync_chain_gen
      always @(posedge clk) begin
        if (!resetn) begin
          sync_chain[i] <= {WIDTH{1'b0}};
        end else begin
          sync_chain[i] <= sync_chain[i-1];
        end
      end
    end
  endgenerate

  // Output is the last flip-flop in the chain
  assign dout = sync_chain[SYNC_DEPTH-1];

  // Logic to determine if the output is stable
  always @(posedge clk) begin
    if (!resetn) begin
      stable <= 1'b0; // Reset stable signal
      stable_counter <= 0; // Reset stable counter
      prev_dout <= {WIDTH{1'b0}}; // Reset previous output
    end else begin
      if (dout == prev_dout) begin
        if (stable_counter < NONZ_STABLE_COUNT - 1) begin
          stable_counter <= stable_counter + 1;
        end else begin
          stable <= 1'b1; // Mark as stable if counter reaches the threshold
        end
      end else begin
        stable_counter <= 0; // Reset counter if dout changes
        stable <= 1'b0; // Not stable if dout changes
      end
      prev_dout <= dout; // Update previous dout for next comparison
    end
  end


endmodule
