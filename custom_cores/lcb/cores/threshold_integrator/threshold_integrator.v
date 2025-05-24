`timescale 1 ns / 1 ps

module threshold_integrator (
  // Inputs
  input   wire         clk               ,
  input   wire         aresetn           ,
  input   wire         enable            ,
  input   wire [ 31:0] window            ,
  input   wire [ 14:0] threshold_average ,
  input   wire         sample_core_done  ,
  input   wire [127:0] value_in_concat   ,
  input   wire [  7:0] value_ready_concat,

  // Outputs
  output  reg         err_overflow  ,
  output  reg         err_underflow ,
  output  reg         over_threshold,
  output  reg         setup_done
);

  //// Internal signals
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
  wire       fifo_full               ;
  wire       wr_en                   ;
  reg [ 3:0] fifo_out_queue_count    ;
  reg [ 3:0] fifo_out_idx            ;
  wire[35:0] fifo_dout               ;
  wire       fifo_empty              ;
  wire       rd_en                   ;
  wire[ 7:0] channel_over_threshold  ;
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


  //// State encoding
  localparam  IDLE          = 3'd0,
              SETUP         = 3'd1,
              WAIT          = 3'd2,
              RUNNING       = 3'd3,
              OUT_OF_BOUNDS = 3'd4,
              ERROR         = 3'd5;


  //// FIFO for rolling integration memory
  fifo_sync #(
    .DATA_WIDTH(36),
    .ADDR_WIDTH(10)
  )
  rolling_sum_mem (
    .clk(clk),
    .aresetn(aresetn),
    .wr_data(fifo_din),
    .wr_en(wr_en),
    .full(fifo_full),
    .rd_data(fifo_dout),
    .rd_en(rd_en),
    .empty(fifo_empty)
  );


  //// FIFO I/O
  always @* begin
    if (fifo_in_queue_count != 0) begin
      fifo_din = queued_fifo_in_sample_sum[fifo_in_queue_count - 1];
    end else begin
      fifo_din = 36'b0;
    end
  end
  assign wr_en = (fifo_in_queue_count != 0);
  assign rd_en = (fifo_out_queue_count != 0);


  //// Global logic
  always @(posedge clk) begin : global_logic
    // Reset logic
    if (~aresetn) begin : reset_logic
      // Zero all individual signals
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
      fifo_out_idx <= 0;

      // Zero all output signals
      over_threshold <= 0;
      err_overflow <= 0;
      err_underflow <= 0;
      setup_done <= 0;

      // Set initial state
      state <= IDLE;
    end else begin : state_logic
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
              over_threshold <= 1;
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
        RUNNING: begin : running_state

          // Error logic
          if (fifo_full & wr_en) begin
            err_overflow <= 1;
            state <= ERROR;
          end
          if (fifo_empty & rd_en) begin
            err_underflow <= 1;
            state <= ERROR;
          end
          
          // Over threshold logic
          if (|channel_over_threshold) begin
            over_threshold <= 1;
            state <= OUT_OF_BOUNDS;
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

          // Outflow FIFO counters (index 1-delayed from fifo_out_queue_count to allow for 1-cycle read delay)
          fifo_out_idx <= fifo_out_queue_count;
          if (fifo_out_queue_count != 0) begin
            // FIFO pop is done in the per-channel logic below
            fifo_out_queue_count <= fifo_out_queue_count - 1;
          end

        end // RUNNING

        OUT_OF_BOUNDS: begin : out_of_bounds_state
          // Stop everything until reset
        end // OUT_OF_BOUNDS

        ERROR: begin : error_state
          // Stop everything until reset
        end // ERROR

      endcase // state
    end
  end // Global logic


  //// Per-channel logic
  genvar i;
  generate // Per-channel logic generate
    for (i = 0; i < 8; i = i + 1) begin : channel_loop
      assign value_in[i] = value_in_concat[16 * (i + 1) - 1 -: 16];
      assign value_ready[i] = value_ready_concat[i];
      assign channel_over_threshold[i] = (total_sum[i] > max_value) ? 1 : 0;

      always @(posedge clk) begin : channel_logic
        if (~aresetn) begin : channel_reset
          // Zero all per-channel signals
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
          // Outflow FIFO logic
          if (fifo_out_idx == i + 1) begin
            queued_fifo_out_sample_sum[i] <= fifo_dout;
          end // Outflow FIFO logic

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
        end // RUNNING
      end // channel_running
    end // channel_loop
  endgenerate // Per-channel logic generate
endmodule
