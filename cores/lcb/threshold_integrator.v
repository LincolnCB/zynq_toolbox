`timescale 1 ns / 1 ps

module threshold_integrator (
  input   wire        clk                    ,
  input   wire        reset                  ,
  input   wire        enable                 ,
  input   wire [31:0] window                 ,
  input   wire [14:0] threshold_average      ,
  input   wire        dac_done               ,
  input   wire [15:0] value_in          [7:0],
  input   wire        value_ready       [7:0],
  output  reg         over_threshold         ,
  output  reg         setup_done
);

  // Internal signals
  reg signed [47:0] min_value                              ;
  reg signed [47:0] max_value                              ;
  reg        [ 4:0] chunk_size                             ;
  reg        [ 4:0] sample_size                            ;
  reg        [19:0] sample_timer_max                       ;
  reg        [ 2:0] sub_average_size                       ;
  reg        [ 4:0] inflow_sub_average_timer               ;
  reg        [19:0] inflow_sample_timer                    ;
  reg        [24:0] outflow_sample_timer                   ;
  reg signed [15:0] inflow_value               [ 7:0]      ;
  reg signed [21:0] sub_average_sum            [ 7:0]      ; // 
  reg signed [35:0] inflow_sample_sum          [ 7:0]      ;
  reg        [ 3:0] fifo_in_queue_count                    ;
  reg signed [35:0] queued_fifo_in_sample_sum  [ 7:0]      ;
  reg        [ 3:0] fifo_out_queue_count                   ;
  reg signed [35:0] queued_fifo_out_sample_sum [ 7:0]      ;
  reg signed [15:0] outflow_value              [ 7:0]      ;
  reg signed [19:0] outflow_remainder          [ 7:0]      ;
  reg signed [20:0] running_total_delta        [ 7:0]      ;
  reg signed [47:0] running_total_sum          [ 7:0]      ;
  reg        [ 2:0] state                                  ;

  // State encoding
  localparam  IDLE          = 3'd0,
              SETUP         = 3'd1,
              WAIT          = 3'd2, 
              RUNNING       = 3'd3,
              OUT_OF_BOUNDS = 3'd4;

  // Main logic
  always @(posedge clk or posedge reset) begin
    // Reset logic
    if (reset) begin
      // Zero all internal signals
      min_value <= 0;
      max_value <= 0;
      chunk_size <= 0;
      sample_size <= 0;
      sample_timer_max <= 0;
      sub_average_size <= 0;
      inflow_sub_average_timer <= 0;
      inflow_sample_timer <= 0;
      outflow_sample_timer <= 0;
      fifo_in_queue_count <= 0;
      fifo_out_queue_count <= 0;
      over_threshold <= 0;
      setup_done <= 0;
      state <= IDLE;
      for (int i = 0; i < 8; i = i + 1) begin
        inflow_value[i] <= 0;
        sub_average_sum[i] <= 0;
        inflow_sample_sum[i] <= 0;
        queued_fifo_in_sample_sum[i] <= 0;
        queued_fifo_out_sample_sum[i] <= 0;
        outflow_value[i] <= 0;
        outflow_remainder[i] <= 0;
        running_total_delta[i] <= 0;
        running_total_sum[i] <= 0;
      end
    end else begin
      case (state)

        // IDLE state, waiting for enable signal
        IDLE: begin
          if (enable) begin
            // Calculate chunk_size
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
            min_value <= -threshold_average * window;
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

        // WAIT state, waiting for DAC to be ready
        WAIT: begin
          if (dac_done) begin
            inflow_sub_average_timer <= (1 << sub_average_size) - 1;
            sample_timer_max <= (1 << sample_size) - 1;
            inflow_sample_timer <= (1 << sample_size) - 1;
            outflow_sample_timer <= window;
            setup_done <= 1;
            state <= RUNNING;
          end
        end // WAIT

        // RUNNING state, main logic
        RUNNING: begin

          // Inflow timers
          if (inflow_sub_average_timer != 0) begin // Sub-average timer
            inflow_sub_average_timer <= inflow_sub_average_timer - 1;
          end else begin
            inflow_sub_average_timer <= (1 << sub_average_size) - 1;
            if (inflow_sample_timer != 0) begin // Sample timer
              inflow_sample_timer <= inflow_sample_timer - 1;
            end else begin
              inflow_sample_timer <= (1 << sample_size) - 1;
              fifo_in_queue_count <= 8;
            end
          end // Inflow timers

          // Inflow channel logic
          for (int i = 0; i < 8; i = i + 1) begin
            // Move new values external values in when valid
            if (value_ready[i]) begin
              inflow_value[i] <= value_in[i] - 16'h8000; // Convert to signed
            end
            // Sub-average logic
            if (inflow_sub_average_timer != 0) begin
              sub_average_sum[i] <= sub_average_sum[i] + inflow_value[i];
            end else begin
              // Remove the sub-average value from the sub-average sum and add the new inflow value
              sub_average_sum[i] <= sub_average_sum[i] - ((sub_average_sum[i] >>> sub_average_size) <<< sub_average_size) + inflow_value[i];
              // Sample sum logic
              if (inflow_sample_timer != 0) begin // Add to sample sum
                inflow_sample_sum[i] <= inflow_sample_sum[i] + (sub_average_sum[i] >>> sub_average_size);
              end else begin // Add to sample sum and move into FIFO queue. Reset sample sum
                queued_fifo_in_sample_sum[i] <= inflow_sample_sum[i] + (sub_average_sum[i] >>> sub_average_size);
                inflow_sample_sum[i] <= 0;
              end
            end
          end // Inflow channel logic
          
          // Inflow FIFO logic
          if (fifo_in_queue_count != 0) begin
            // TODO: Push to FIFO
            fifo_in_queue_count <= fifo_in_queue_count - 1;
          end // Inflow FIFO logic

          // Outflow timer
          if (outflow_sample_timer != 0) begin
            outflow_sample_timer <= outflow_sample_timer - 1;
            if (outflow_sample_timer == 16) begin // Initiate FIFO popping to queue
              fifo_out_queue_count <= 8;
            end
          end else begin
            outflow_sample_timer <= (1 << chunk_size) - 1;
          end // Outflow timer

          // Outflow channel logic
          for (int i = 0; i < 8; i = i + 1) begin
            // Move queued samples in to outflow value and remainder
            if (outflow_sample_timer == 0) begin
              outflow_value[i] <= queued_fifo_out_sample_sum[i] >>> sample_size;
              // TODO: This rounds down negative numbers, and should round towards zero
              outflow_remainder[i] <= (queued_fifo_out_sample_sum[i] - (queued_fifo_out_sample_sum[i] >>> sample_size));
            end
          end // Outflow channel logic

          // Outflow FIFO logic
          if (fifo_out_queue_count != 0) begin
            // TODO: Pop from FIFO
            fifo_out_queue_count <= fifo_out_queue_count - 1;
          end // Outflow FIFO logic

          // Running total logic
          for (int i = 0; i < 8; i = i + 1) begin
            if (outflow_remainder >= 0) begin
              running_total_delta[i] <= (outflow_timer >= outflow_remainder[i])
                                      ? inflow_value[i] - outflow_value[i]
                                      : inflow_value[i] - outflow_value[i] - 1;
            else
              running_total_delta[i] <= (outflow_timer >= -outflow_remainder[i])
                                      ? inflow_value[i] - outflow_value[i]
                                      : inflow_value[i] - outflow_value[i] + 1;
            end
            
            // Check for over threshold while avoiding overflow
            if (running_total_delta[i] < min_value || running_total_delta[i] > max_value) begin
              over_threshold <= 1;
              state <= OUT_OF_BOUNDS;
            end else if (running_total_delta[i] < 0 && min_value - running_total_delta[i] > running_total_sum[i]) begin
              over_threshold <= 1;
              state <= OUT_OF_BOUNDS;
            end else if (running_total_delta[i] > 0 && max_value - running_total_delta[i] < running_total_sum[i]) begin
              over_threshold <= 1;
              state <= OUT_OF_BOUNDS;
            end else begin
              running_total_sum[i] <= running_total_sum[i] + running_total_delta[i];
            end
              
          end // Running total logic

        end // RUNNING
        OUT_OF_BOUNDS: begin
          // Stop everything until reset
        end
      endcase // state
    end
  end // always
endmodule
