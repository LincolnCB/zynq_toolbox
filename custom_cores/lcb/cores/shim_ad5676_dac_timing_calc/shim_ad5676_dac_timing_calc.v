`timescale 1ns / 1ps

module shim_ad5676_dac_timing_calc (
  input  wire        clk,
  input  wire        resetn,
  
  input  wire [31:0] spi_clk_freq_hz, // SPI clock frequency in Hz
  input  wire        calc,            // Start calculation signal
  
  output reg  [4:0]  n_cs_high_time,  // Calculated n_cs high time in cycles (max 31)
  output reg         done,            // Calculation complete
  output reg         lock_viol        // Error if frequency changes during calc
);

  ///////////////////////////////////////////////////////////////////////////////
  // Constants
  ///////////////////////////////////////////////////////////////////////////////

  // Update time (ns) for AD5676 (datasheet: time between rising edges of n_cs)
  localparam integer T_UPDATE_NS_AD5676 = 830;
  localparam integer T_MIN_N_CS_HIGH_NS = 30;

  // SPI command bit width
  localparam integer SPI_CMD_BITS = 24;

  ///////////////////////////////////////////////////////////////////////////////
  // Internal Signals
  ///////////////////////////////////////////////////////////////////////////////

  // State machine
  localparam S_IDLE           = 3'd0;
  localparam S_CALC_UPDATE    = 3'd1;
  localparam S_CALC_MIN_HIGH  = 3'd2;
  localparam S_CALC_RESULT    = 3'd3;
  localparam S_DONE           = 3'd4;

  reg [ 2:0] state;
  reg [31:0] spi_clk_freq_hz_latched;
  
  // Intermediate calculation results
  reg [31:0] min_cycles_for_t_update;
  reg [31:0] min_cycles_for_t_min_n_cs_high;
  reg [31:0] final_result;
  
  // Division state machine
  reg [ 5:0] div_count;
  reg [63:0] dividend;
  reg [31:0] divisor;
  reg [31:0] quotient;
  reg [63:0] remainder;

  ///////////////////////////////////////////////////////////////////////////////
  // Logic
  ///////////////////////////////////////////////////////////////////////////////

  always @(posedge clk) begin
    if (!resetn) begin
      state <= S_IDLE;
      done <= 1'b0;
      lock_viol <= 1'b0;
      n_cs_high_time <= 5'd0;
      spi_clk_freq_hz_latched <= 32'd0;
      min_cycles_for_t_update <= 32'd0;
      min_cycles_for_t_min_n_cs_high <= 32'd0;
      final_result <= 32'd0;
      div_count <= 6'd0;
      dividend <= 64'd0;
      divisor <= 32'd0;
      quotient <= 32'd0;
      remainder <= 64'd0;
    end else begin
      case (state)
        S_IDLE: begin
          done <= 1'b0;
          lock_viol <= 1'b0;
          if (calc) begin
            spi_clk_freq_hz_latched <= spi_clk_freq_hz;
            state <= S_CALC_UPDATE;
            
            // Setup division for min_cycles_for_t_update
            dividend <= T_UPDATE_NS_AD5676 * spi_clk_freq_hz + 64'd999_999_999;
            divisor <= 32'd1_000_000_000;
            div_count <= 6'd0;
            quotient <= 32'd0;
            remainder <= 64'd0;
          end
        end

        //// ---- Calcuate the minimum cycles to get at least the required t_update time
        S_CALC_UPDATE: begin
          // Check for frequency change during calculation
          if (spi_clk_freq_hz != spi_clk_freq_hz_latched) begin
            lock_viol <= 1'b1;
            state <= S_IDLE;
          end else if (!calc) begin
            // calc went low, reset
            state <= S_IDLE;
          end else begin
            // Perform division for number of cycles for an update (non-restoring division)
            if (div_count < 32) begin
              remainder <= {remainder[62:0], dividend[63-div_count]};
              if (remainder >= {32'd0, divisor}) begin
                remainder <= remainder - {32'd0, divisor};
                quotient[31-div_count] <= 1'b1;
              end else begin
                quotient[31-div_count] <= 1'b0;
              end
              div_count <= div_count + 1;
            end else begin
              // Division complete for the number of cycles for an update
              min_cycles_for_t_update <= quotient > SPI_CMD_BITS ? quotient : 0;
              
              // Setup division for min_cycles_for_t_min_n_cs_high
              dividend <= T_MIN_N_CS_HIGH_NS * spi_clk_freq_hz_latched + 64'd999_999_999;
              divisor <= 32'd1_000_000_000;
              div_count <= 6'd0;
              quotient <= 32'd0;
              remainder <= 64'd0;
              
              state <= S_CALC_MIN_HIGH;
            end
          end
        end

        //// ---- Calculate the minimum cycles to get at least the required t_min_n_cs_high time (also ensure at least 4 cycles)
        S_CALC_MIN_HIGH: begin
          // Check for frequency change during calculation
          if (spi_clk_freq_hz != spi_clk_freq_hz_latched) begin
            lock_viol <= 1'b1;
            state <= S_IDLE;
          end else if (!calc) begin
            // calc went low, reset
            state <= S_IDLE;
          end else begin
            // Perform division for min_cycles_for_t_min_n_cs_high
            if (div_count < 32) begin
              remainder <= {remainder[62:0], dividend[63-div_count]};
              if (remainder >= {32'd0, divisor}) begin
                remainder <= remainder - {32'd0, divisor};
                quotient[31-div_count] <= 1'b1;
              end else begin
                quotient[31-div_count] <= 1'b0;
              end
              div_count <= div_count + 1;
            end else begin
              // Ensure n_cs high time is at least 4 cycles to do DAC value loading and calibration
              if (quotient < 4) begin
                min_cycles_for_t_min_n_cs_high <= 32'd4;
              end else begin
                min_cycles_for_t_min_n_cs_high <= quotient;
              end
              
              state <= S_CALC_RESULT;
            end
          end
        end

        //// ---- Calculate the final n_cs_high_time based on the two previous results
        S_CALC_RESULT: begin
          // Check for frequency change during calculation
          if (spi_clk_freq_hz != spi_clk_freq_hz_latched) begin
            lock_viol <= 1'b1;
            state <= S_IDLE;
          end else if (!calc) begin
            // calc went low, reset
            state <= S_IDLE;
            end else begin
            // Calculate final result based on the following logic:
            // final_result = max(min_cycles_for_t_update, min_cycles_for_t_min_n_cs_high);
            if (min_cycles_for_t_update < min_cycles_for_t_min_n_cs_high) begin
              final_result <= min_cycles_for_t_min_n_cs_high;
            end else begin
              final_result <= min_cycles_for_t_update;
            end
            state <= S_DONE;
            end
          end

          //// ---- Stay in this state to check if calc goes low or frequency changes
          S_DONE: begin
            // Check for frequency change during calculation
            if (spi_clk_freq_hz != spi_clk_freq_hz_latched) begin
            lock_viol <= 1'b1;
            state <= S_IDLE;
            end else if (!calc) begin
            // calc went low, reset
            state <= S_IDLE;
            end else begin
            // Cap n_cs_high_time at 31 (at the maximum 50MHz SPI clock, this plus the command bits is 1120ns, which is >830ns required)
            if (final_result > 31) begin
              n_cs_high_time <= 5'd31;
            end else begin
              n_cs_high_time <= final_result[4:0];
            end
            done <= 1'b1;
            // Stay in this state until calc goes low
            end
          end

        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end

endmodule
