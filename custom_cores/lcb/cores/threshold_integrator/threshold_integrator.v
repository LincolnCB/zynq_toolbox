`timescale 1 ns / 1 ps

module threshold_integrator (
  // Inputs
  input   wire         clk               ,
  input   wire         rst               ,
  input   wire         enable            ,
  input   wire [ 31:0] window            ,
  input   wire [ 14:0] threshold_average ,
  input   wire         sample_core_done  ,
  input   wire [127:0] value_in_concat   ,
  input   wire [  7:0] value_ready_concat,

  // Outputs
  output  reg         err_overflow  ,
  output  reg         err_underflow ,
  output  wire        over_threshold,
  output  reg         setup_done
);

  // Internal signals
  wire[15:0] value_in   [7:0];
  wire       value_ready[7:0];
  reg [47:0] max_value               ;
  reg [ 4:0] chunk_size              ;
  reg [24:0] chunk_mask              ;
  reg [ 4:0] sample_size             ;
  reg [19:0] sample_mask             ;
  reg [ 2:0] sub_average_size        ;
  reg [ 4:0] sub_average_mask        ;
  reg [ 4:0] inflow_sub_average_timer;
  reg [19:0] inflow_sample_timer     ;
  reg [24:0] outflow_timer           ;
  reg [ 3:0] fifo_in_queue_count     ;
  reg [35:0] fifo_din                ;
  wire       wr_en                   ;
  wire       overflow                ;
  reg [ 3:0] fifo_out_queue_count    ;
  wire[35:0] fifo_dout               ;
  wire       rd_en                   ;
  wire       underflow               ;
  reg [ 2:0] state                   ;
  reg [15:0] inflow_value               [ 7:0];
  reg [21:0] sub_average_sum            [ 7:0];
  reg [35:0] inflow_sample_sum          [ 7:0];
  reg [35:0] queued_fifo_in_sample_sum  [ 7:0];
  reg [35:0] queued_fifo_out_sample_sum [ 7:0];
  reg [15:0] outflow_value              [ 7:0];
  reg [19:0] outflow_remainder          [ 7:0];
  reg signed [17:0] sum_delta   [ 7:0];
  reg signed [48:0] total_sum   [ 7:0];
  reg [ 7:0] channel_over_threshold;

  // State encoding
  localparam  IDLE          = 3'd0,
              SETUP         = 3'd1,
              WAIT          = 3'd2,
              RUNNING       = 3'd3,
              OUT_OF_BOUNDS = 3'd4,
              ERROR         = 3'd5;

  // Over threshold if any channel is over threshold
  assign over_threshold = |channel_over_threshold;

  //// FIFO instantiation
  // xpm_fifo_sync: Synchronous FIFO
  // Xilinx Parameterized Macro, version 2024.1
  xpm_fifo_sync #(
    .FIFO_MEMORY_TYPE("block"),    // String
    .FIFO_READ_LATENCY(0),         // DECIMAL
    .FIFO_WRITE_DEPTH(1024),       // DECIMAL
    .RD_DATA_COUNT_WIDTH(11),      // DECIMAL
    .READ_DATA_WIDTH(36),          // DECIMAL
    .READ_MODE("fwft"),            // String
    .USE_ADV_FEATURES("0101"),     // Enable: overflow, underflow
    .WRITE_DATA_WIDTH(36),         // DECIMAL
    .WR_DATA_COUNT_WIDTH(11)       // DECIMAL
  )
  xpm_fifo_sync_inst (
    .dout(fifo_dout),              // READ_DATA_WIDTH-bit output: Read Data: The output data bus is driven
                                    // when reading the FIFO.
    .overflow(overflow),           // 1-bit output: Overflow: This signal indicates that a write request
                                    // (wren) during the prior clock cycle was rejected, because the FIFO is
                                    // full. Overflowing the FIFO is not destructive to the contents of the
                                    // FIFO.
    .underflow(underflow),         // 1-bit output: Underflow: Indicates that the read request (rd_en) during
                                    // the previous clock cycle was rejected because the FIFO is empty. Under
                                    // flowing the FIFO is not destructive to the FIFO.
    .din(fifo_din),                // WRITE_DATA_WIDTH-bit input: Write Data: The input data bus used when
                                    // writing the FIFO.
    .rd_en(rd_en),                 // 1-bit input: Read Enable: If the FIFO is not empty, asserting this
                                    // signal causes data (on dout) to be read from the FIFO. Must be held
                                    // active-low when rd_rst_busy is active high.
    .rst(rst),                     // 1-bit input: Reset: Must be synchronous to wr_clk. The clock(s) can be
                                    // unstable at the time of applying reset, but reset must be released only
                                    // after the clock(s) is/are stable.
    .wr_clk(clk),                  // 1-bit input: Write clock: Used for write operation. wr_clk must be a
                                    // free running clock.
    .wr_en(wr_en)                  // 1-bit input: Write Enable: If the FIFO is not full, asserting this
                                    // signal causes data (on din) to be written to the FIFO Must be held
                                    // active-low when rst or wr_rst_busy or rd_rst_busy is active high
  );
  // End of xpm_fifo_sync_inst instantiation

  // FIFO I/O
  always @* begin
    if (fifo_in_queue_count != 0) begin
      fifo_din = queued_fifo_in_sample_sum[fifo_in_queue_count - 1];
    end else begin
      fifo_din = 36'b0;
    end
  end
  assign wr_en = (fifo_in_queue_count != 0);
  assign rd_en = (fifo_out_queue_count != 0);

  // Global logic
  always @(posedge clk or posedge rst) begin
    // Reset logic
    if (rst) begin
      // Zero all internal signals
      max_value <= 0;
      chunk_size <= 0;
      chunk_mask <= 0;
      sample_size <= 0;
      sample_mask <= 0;
      sub_average_size <= 0;
      sub_average_mask <= 0;
      inflow_sub_average_timer <= 0;
      inflow_sample_timer <= 0;
      outflow_timer <= 0;
      fifo_in_queue_count <= 0;
      fifo_out_queue_count <= 0;

      // Zero all output signals
      channel_over_threshold <= 8'b0;
      err_overflow <= 0;
      err_underflow <= 0;
      setup_done <= 0;

      // Set initial state
      state <= IDLE;
    end else begin
      case (state)

        // IDLE state, waiting for enable signal
        IDLE: begin
          if (enable) begin
            // Calculate chunk_size (MSB of window - 6)
            if (window[31]) begin
              chunk_size <= 25;
            end else if (window[30]) begin
              chunk_size <= 24;
            end else if (window[29]) begin
              chunk_size <= 23;
            end else if (window[28]) begin
              chunk_size <= 22;
            end else if (window[27]) begin
              chunk_size <= 21;
            end else if (window[26]) begin
              chunk_size <= 20;
            end else if (window[25]) begin
              chunk_size <= 19;
            end else if (window[24]) begin
              chunk_size <= 18;
            end else if (window[23]) begin
              chunk_size <= 17;
            end else if (window[22]) begin
              chunk_size <= 16;
            end else if (window[21]) begin
              chunk_size <= 15;
            end else if (window[20]) begin
              chunk_size <= 14;
            end else if (window[19]) begin
              chunk_size <= 13;
            end else if (window[18]) begin
              chunk_size <= 12;
            end else if (window[17]) begin
              chunk_size <= 11;
            end else if (window[16]) begin
              chunk_size <= 10;
            end else if (window[15]) begin
              chunk_size <= 9;
            end else if (window[14]) begin
              chunk_size <= 8;
            end else if (window[13]) begin
              chunk_size <= 7;
            end else if (window[12]) begin
              chunk_size <= 6;
            end else if (window[11]) begin
              chunk_size <= 5;
            end else begin // Disallowed size of window
              channel_over_threshold <= 8'b111111111;
              state <= OUT_OF_BOUNDS;
            end

            // Calculate min/max values
            max_value <= threshold_average * window;

            state <= SETUP;
          end
        end // IDLE

        // SETUP state, intermediate calculations
        SETUP: begin
          sub_average_size <= (chunk_size > 20) ? (chunk_size - 20) : 0;
          sample_size <= (chunk_size > 20) ? 20 : chunk_size;
          state <= WAIT;
        end // SETUP

        // WAIT state, waiting for sample core (DAC/ADC) to finish setting up
        WAIT: begin
          if (sample_core_done) begin
            // Calculate masks
            chunk_mask <= (1 << chunk_size) - 1;
            sample_mask <= (1 << sample_size) - 1;
            sub_average_mask <= (1 << sub_average_size) - 1;
            // Initialize timers
            inflow_sub_average_timer <= (1 << sub_average_size) - 1;
            inflow_sample_timer <= (1 << sample_size) - 1;
            outflow_timer <= window - 1;
            setup_done <= 1;
            state <= RUNNING;
          end
        end // WAIT

        // RUNNING state, main logic
        RUNNING: begin

          // Error logic
          if (overflow) begin
            err_overflow <= 1;
            state <= ERROR;
          end
          if (underflow) begin
            err_underflow <= 1;
            state <= ERROR;
          end

          // Inflow timers
          if (inflow_sub_average_timer != 0) begin // Sub-average timer
            inflow_sub_average_timer <= inflow_sub_average_timer - 1;
          end else begin
            inflow_sub_average_timer <= sub_average_mask;
            if (inflow_sample_timer != 0) begin // Sample timer
              inflow_sample_timer <= inflow_sample_timer - 1;
            end else begin
              inflow_sample_timer <= sample_mask;
              fifo_in_queue_count <= 8;
            end
          end // Inflow timers

          // Inflow FIFO counter
          if (fifo_in_queue_count != 0) begin
            // FIFO push is done in FIFO I/O always block above
            fifo_in_queue_count <= fifo_in_queue_count - 1;
          end // Inflow FIFO counter

          // Outflow timer
          if (outflow_timer != 0) begin
            outflow_timer <= outflow_timer - 1;
            if (outflow_timer == 16) begin // Initiate FIFO popping to queue
              fifo_out_queue_count <= 8;
            end
          end else begin
            outflow_timer <= chunk_mask;
          end // Outflow timer

          // Outflow FIFO logic
          if (fifo_out_queue_count != 0) begin
            queued_fifo_out_sample_sum[fifo_out_queue_count - 1] <= fifo_dout;
            fifo_out_queue_count <= fifo_out_queue_count - 1;
          end // Outflow FIFO logic

        end // RUNNING

        OUT_OF_BOUNDS: begin
          // Stop everything until reset
        end // OUT_OF_BOUNDS

        ERROR: begin
          // Stop everything until reset
        end // ERROR

      endcase // state
    end
  end // Global logic

  // Per-channel logic
  genvar i;
  generate // Per-channel logic generate
    for (i = 0; i < 8; i = i + 1) begin : channel_loop
      assign value_in[i] = value_in_concat[16 * (i + 1) - 1 -: 16];
      assign value_ready[i] = value_ready_concat[i];

      always @(posedge clk or posedge rst) begin
        if (rst) begin : channel_reset
          inflow_value[i] = 0;
          sub_average_sum[i] = 0;
          inflow_sample_sum[i] = 0;
          queued_fifo_in_sample_sum[i] = 0;
          queued_fifo_out_sample_sum[i] = 0;
          outflow_value[i] = 0;
          outflow_remainder[i] = 0;
          total_sum[i] = 0;
          sum_delta[i] = 0;
        end else if (state == RUNNING) begin : channel_running
          //// Inflow logic
          // Move new values external values in when valid
          if (value_ready[i]) begin
            inflow_value[i] <= (value_in[i][15]) ? (value_in[i] - 32768) : (32768 - value_in[i]);
          end
          // Sub-average logic
          if (inflow_sub_average_timer != 0) begin
            sub_average_sum[i] <= sub_average_sum[i] + inflow_value[i];
          end else begin
            // Remove the sub-average value from the sub-average sum and add the new inflow value
            sub_average_sum[i] <= (sub_average_sum[i] & (1 << sub_average_size - 1)) + inflow_value[i];
            // Sample sum logic
            if (inflow_sample_timer != 0) begin // Add to sample sum
              inflow_sample_sum[i] <= inflow_sample_sum[i] + (sub_average_sum[i] >> sub_average_size);
            end else begin // Add to sample sum and move into FIFO queue. Reset sample sum
              queued_fifo_in_sample_sum[i] <= inflow_sample_sum[i] + (sub_average_sum[i] >> sub_average_size);
              inflow_sample_sum[i] <= 0;
            end
          end

          //// Outflow logic
          // Move queued samples in to outflow value and remainder
          if (outflow_timer == 0) begin
            outflow_value[i] <= queued_fifo_out_sample_sum[i] >> sample_size;
            outflow_remainder[i] <= queued_fifo_out_sample_sum[i] & sample_mask;
          end

          //// Sum logic
          // Pipeline the delta to the running total
          sum_delta[i] <= ((outflow_timer & sample_mask) < outflow_remainder[i])
                  ? $signed({2'b00, inflow_value[i]}) - $signed({2'b00, outflow_value[i]} + 1)
                  : $signed({2'b00, inflow_value[i]}) - $signed({2'b00, outflow_value[i]});
          total_sum[i] <= total_sum[i] + sum_delta[i];
          if (total_sum[i] > max_value) begin
            channel_over_threshold[i] <= 1;
            state <= OUT_OF_BOUNDS;
          end
        end // RUNNING
      end // channel_running
    end // channel_loop
  endgenerate // Per-channel logic generate
endmodule
