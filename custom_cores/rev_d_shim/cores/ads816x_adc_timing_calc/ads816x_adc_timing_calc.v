`timescale 1ns / 1ps

module ads816x_adc_timing_calc #(
  parameter ADS_MODEL_ID = 8 // 8 for ADS8168, 7 for ADS8167, 6 for ADS8166
)(
  input  wire        clk,
  input  wire        resetn,
  
  input  wire [31:0] spi_clk_freq_hz, // SPI clock frequency in Hz
  input  wire        calc,            // Start calculation signal
  
  output reg  [7:0]  n_cs_high_time,     // Calculated n_cs high time in cycles (minus 1)
                                         //   Range: 2 to 255 (corresponds to 3 to 256 cycles, 60ns to 5120ns at 50MHz SPI clock)
  output reg  [2:0]  miso_halfclk_delay, // Calculated MISO half-clock delay (floor((spi_clk_freq * 4 + 1476395008) >> 30)), capped at 7
  output reg         done,               // Calculation complete
  output reg         lock_viol           // Error if frequency changes during calc
);

  ///////////////////////////////////////////////////////////////////////////////
  // Constants
  ///////////////////////////////////////////////////////////////////////////////

  // Conversion and cycle times (ns) for each ADC model
  // Use a power of 2 unit for easier calculations -- calling these NiS
  // 2^30 (0x4000_0000) NiS = 10^9 (1000_000_000) NS = 1 second
  // Round up to make sure we don't underestimate
  // This allows the overall calculation to be: f(Hz) * T(nis) / 2^30
  //   which changes a division into a bit-shift right by 30
  // ADS8168:  660 ns  conv, 1000 ns  cycle
  //       ->  709 nis conv, 1074 nis cycle
  // ADS8167: 1200 ns  conv, 2000 ns  cycle
  //       -> 1289 nis conv, 2148 nis cycle
  // ADS8166: 2500 ns  conv, 4000 ns  cycle
  //       -> 2685 nis conv, 4295 nis cycle
  // Select conversion and cycle times based on ADS_MODEL_ID at compile time
  localparam integer  T_CONV_NiS =
    (ADS_MODEL_ID == 8) ? 709 :
    (ADS_MODEL_ID == 7) ? 1289 :
    (ADS_MODEL_ID == 6) ? 2685 :
    2685;
  localparam integer T_CYCLE_NiS =
    (ADS_MODEL_ID == 8) ? 1074 :
    (ADS_MODEL_ID == 7) ? 2148 :
    (ADS_MODEL_ID == 6) ? 4295 :
    4295;
  // Indicate the bitwidth of the conversion and cycle times to optimize multiplication
  localparam integer T_CONV_NiS_BITS =
    (ADS_MODEL_ID == 8) ? 10 :
    (ADS_MODEL_ID == 7) ? 11 :
    (ADS_MODEL_ID == 6) ? 12 :
    12;
  localparam integer T_CYCLE_NiS_BITS =
    (ADS_MODEL_ID == 8) ? 11 :
    (ADS_MODEL_ID == 7) ? 12 :
    (ADS_MODEL_ID == 6) ? 13 :
    13;

  // MISO half-clock delay calculation constants
  localparam integer MISO_DELAY_NiS = 5; // 4.5ns -> 5NiS
  localparam integer MISO_DELAY_NiS_BITS = 5;
  localparam integer MISO_DELAY_OFFSET = 32'h40000000; // 1.0 * 2^30

  // SPI command bit width
  localparam integer OTF_CMD_BITS = 16;

  ///////////////////////////////////////////////////////////////////////////////
  // Internal Signals
  ///////////////////////////////////////////////////////////////////////////////

  // State machine
  localparam S_IDLE         = 3'd0;
  localparam S_CALC_CONV    = 3'd1;
  localparam S_CALC_CYCLE   = 3'd2;
  localparam S_CALC_RESULT  = 3'd3;
  localparam S_DONE         = 3'd4;

  reg [ 2:0] state;
  reg [31:0] spi_clk_freq_hz_latched;
  
  // Intermediate calculation results
  reg [31:0] min_cycles_for_t_conv;
  reg [31:0] min_cycles_for_t_cycle;
  reg [31:0] final_result;
  
  // Multiplication state machine (shift-add algorithm)
  reg [ 3:0] mult_count;      // 4 bits sufficient for max 16 bits
  reg [15:0] mult_shift;      // Shift a bit through this to control multiplication
  reg [31:0] multiplicand;    // The constant (T_CONV_NiS or T_CYCLE_NiS or MISO_DELAY_NiS)
  reg [31:0] multiplier;      // The frequency value
  reg [63:0] mult_accumulator;
  wire [63:0] mult_result_rounded_up;

  // MISO half-clock delay calculation intermediate
  reg [35:0] miso_delay_calc;

  ///////////////////////////////////////////////////////////////////////////////
  // Logic
  ///////////////////////////////////////////////////////////////////////////////

  assign mult_result_rounded_up = mult_accumulator + 64'h3FFFFFFF; // Add 2^30 - 1 for rounding

  always @(posedge clk) begin
    if (!resetn) begin
      state <= S_IDLE;
      done <= 1'b0;
      lock_viol <= 1'b0;
      n_cs_high_time <= 8'd0;
      miso_delay_calc <= 36'd0;
      miso_halfclk_delay <= 3'd1;
      spi_clk_freq_hz_latched <= 32'd0;
      min_cycles_for_t_conv <= 32'd0;
      min_cycles_for_t_cycle <= 32'd0;
      final_result <= 32'd0;
      mult_count <= 4'd0;
      mult_shift <= 16'd0;
      multiplicand <= 32'd0;
      multiplier <= 32'd0;
      mult_accumulator <= 64'd0;
    end else begin
      case (state)
        S_IDLE: begin
          done <= 1'b0;
          lock_viol <= 1'b0;
          if (calc) begin
            spi_clk_freq_hz_latched <= spi_clk_freq_hz;
            state <= S_CALC_CONV;
            
            // Setup multiplication for T_CONV_NiS * spi_clk_freq_hz
            multiplicand <= T_CONV_NiS;
            multiplier <= spi_clk_freq_hz;
            mult_count <= 4'd0;
            mult_shift <= 16'd0;
            mult_accumulator <= 64'd0;
          end
        end

        //// ---- Multiply T_CONV_NiS * spi_clk_freq_hz using shift-add
        S_CALC_CONV: begin
          // Check for frequency change during calculation
          if (spi_clk_freq_hz != spi_clk_freq_hz_latched) begin
            lock_viol <= 1'b1;
            state <= S_IDLE;
          end else if (!calc) begin
            // calc went low, reset
            state <= S_IDLE;
          end else begin
            if (mult_shift < T_CONV_NiS) begin
              // Shift-add multiplication: if current bit of multiplicand is 1, add shifted multiplier
              if (multiplicand[mult_count]) begin
                mult_accumulator <= mult_accumulator + ({32'd0, multiplier} << mult_count);
              end
              mult_shift <= 16'd1 << mult_count;
              mult_count <= mult_count + 1;
            end else begin
              // Multiplication complete, add 2^30 - 1 for rounding, then shift right by 30 bits (equivalent to divide by 2^30)
              // Ensure n_cs high time is at least 3 cycles to give the ADC core enough time to send data
              min_cycles_for_t_conv <= (mult_result_rounded_up[61:30]) < 3 ? 3 : (mult_result_rounded_up[61:30]);
              // Setup multiplication for T_CYCLE_NiS * spi_clk_freq_hz_latched
              multiplicand <= T_CYCLE_NiS;
              multiplier <= spi_clk_freq_hz_latched;
              mult_count <= 4'd0;
              mult_accumulator <= 64'd0;
              
              state <= S_CALC_CYCLE;
            end
          end
        end

        //// ---- Multiply T_CYCLE_NiS * spi_clk_freq_hz using shift-add
        S_CALC_CYCLE: begin
          // Check for frequency change during calculation
          if (spi_clk_freq_hz != spi_clk_freq_hz_latched) begin
            lock_viol <= 1'b1;
            state <= S_IDLE;
          end else if (!calc) begin
            // calc went low, reset
            state <= S_IDLE;
          end else begin
            if (mult_shift < T_CYCLE_NiS) begin
              // Shift-add multiplication: if current bit of multiplicand is 1, add shifted multiplier
              if (multiplicand[mult_count]) begin
                mult_accumulator <= mult_accumulator + ({32'd0, multiplier} << mult_count);
              end
              mult_shift <= 16'd1 << mult_count;
              mult_count <= mult_count + 1;
            end else begin
              // Multiplication complete, add 2^30 - 1 for rounding, then shift right by 30 bits (equivalent to divide by 2^30)
              // Set the min cycles for t_cycle to be the result minus OTF command bits (16), min of 0
              min_cycles_for_t_cycle <= (mult_result_rounded_up[61:30]) > OTF_CMD_BITS ? ((mult_result_rounded_up[61:30]) - OTF_CMD_BITS) : 0;
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
            // final_result = max(min_cycles_for_t_conv, min_cycles_for_t_cycle) - 1
            if (min_cycles_for_t_conv < min_cycles_for_t_cycle) begin
              final_result <= min_cycles_for_t_cycle;
            end else begin
              final_result <= min_cycles_for_t_conv;
            end
            // Setup multiplication for MISO_DELAY_NiS * spi_clk_freq_hz_latched
            multiplicand <= MISO_DELAY_NiS;
            multiplier <= spi_clk_freq_hz_latched;
            mult_count <= 4'd0;
            mult_accumulator <= 64'd0;
            state <= 3'd5; // S_CALC_MISO_DELAY
          end
        end

        // S_CALC_MISO_DELAY: calculate MISO half-clock delay
        3'd5: begin
          if (spi_clk_freq_hz != spi_clk_freq_hz_latched) begin
            lock_viol <= 1'b1;
            state <= S_IDLE;
          end else if (!calc) begin
            state <= S_IDLE;
          end else begin
            if (mult_shift < MISO_DELAY_NiS) begin
              if (multiplicand[mult_count]) begin
                mult_accumulator <= mult_accumulator + ({32'd0, multiplier} << mult_count);
              end
              mult_shift <= 16'd1 << mult_count;
              mult_count <= mult_count + 1;
            end else begin
              miso_delay_calc <= (mult_accumulator + MISO_DELAY_OFFSET);
              state <= S_DONE;
            end
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
            // Cap n_cs_high_time at 255 (at the maximum 50MHz SPI clock, 256 + 16 bits is 5440ns, which is over the maximum 4000ns required)
            if (final_result > 255) begin
              n_cs_high_time <= 8'd255;
            end else begin
              n_cs_high_time <= final_result[7:0] - 1; // Truncate to 8 bits
            end
            // Calculate miso_halfclk_delay, capped at 7
            if (miso_delay_calc[35:30] > 7) begin
              miso_halfclk_delay <= 3'd7;
            end else begin
              miso_halfclk_delay <= miso_delay_calc[32:30];
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
