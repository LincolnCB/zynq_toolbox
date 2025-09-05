`timescale 1ns / 1ps

module shim_ads816x_adc_timing_calc #(
  parameter ADS_MODEL_ID = 8 // 8 for ADS8168, 7 for ADS8167, 6 for ADS8166
)(
  input  wire        clk,
  input  wire        resetn,
  
  input  wire [31:0] spi_clk_freq_hz, // SPI clock frequency in Hz
  input  wire        calc,            // Start calculation signal
  
  output reg  [7:0]  n_cs_high_time,  // Calculated n_cs high time in cycles (max 255)
  output reg         done,            // Calculation complete
  output reg         lock_viol        // Error if frequency changes during calc
);

  ///////////////////////////////////////////////////////////////////////////////
  // Constants
  ///////////////////////////////////////////////////////////////////////////////

  // Conversion and cycle times (ns) for each ADC model
  localparam integer T_CONV_NS_ADS8168  = 660;
  localparam integer T_CONV_NS_ADS8167  = 1200;
  localparam integer T_CONV_NS_ADS8166  = 2500;
  localparam integer T_CYCLE_NS_ADS8168 = 1000;
  localparam integer T_CYCLE_NS_ADS8167 = 2000;
  localparam integer T_CYCLE_NS_ADS8166 = 4000;

  // SPI command bit width
  localparam integer OTF_CMD_BITS = 16;

  // Select conversion and cycle times based on ADS_MODEL_ID at compile time
  localparam integer T_CONV_NS =
    (ADS_MODEL_ID == 8) ? T_CONV_NS_ADS8168 :
    (ADS_MODEL_ID == 7) ? T_CONV_NS_ADS8167 :
    (ADS_MODEL_ID == 6) ? T_CONV_NS_ADS8166 :
    T_CONV_NS_ADS8166;

  localparam integer T_CYCLE_NS =
    (ADS_MODEL_ID == 8) ? T_CYCLE_NS_ADS8168 :
    (ADS_MODEL_ID == 7) ? T_CYCLE_NS_ADS8167 :
    (ADS_MODEL_ID == 6) ? T_CYCLE_NS_ADS8166 :
    T_CYCLE_NS_ADS8166;

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
      n_cs_high_time <= 9'd0;
      spi_clk_freq_hz_latched <= 32'd0;
      min_cycles_for_t_conv <= 32'd0;
      min_cycles_for_t_cycle <= 32'd0;
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
            state <= S_CALC_CONV;
            
            // Setup division for min_cycles_for_t_conv
            dividend <= T_CONV_NS * spi_clk_freq_hz + 64'd999_999_999;
            divisor <= 32'd1_000_000_000;
            div_count <= 6'd0;
            quotient <= 32'd0;
            remainder <= 64'd0;
          end
        end

        //// ---- Calculate the minimum cycles to get at least the required t_conv time (minimum 3 cycles for the core to anticipate starting the MISO read)
        S_CALC_CONV: begin
          // Check for frequency change during calculation
          if (spi_clk_freq_hz != spi_clk_freq_hz_latched) begin
            lock_viol <= 1'b1;
            state <= S_IDLE;
          end else if (!calc) begin
            // calc went low, reset
            state <= S_IDLE;
          end else begin
            // Perform division for number of cycles for t_conv (non-restoring division)
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
              // Division complete for the number of cycles for t_conv
              min_cycles_for_t_conv <= quotient < 3 ? 3 : quotient;
              
              // Setup division for min_cycles_for_t_cycle
              dividend <= T_CYCLE_NS * spi_clk_freq_hz_latched + 64'd999_999_999;
              divisor <= 32'd1_000_000_000;
              div_count <= 6'd0;
              quotient <= 32'd0;
              remainder <= 64'd0;
              
              state <= S_CALC_CYCLE;
            end
          end
        end

        //// ---- Calculate the minimum cycles to get at least the required t_cycle time (past the required OTF_CMD_BITS, as this time includes the command)
        S_CALC_CYCLE: begin
          // Check for frequency change during calculation
          if (spi_clk_freq_hz != spi_clk_freq_hz_latched) begin
            lock_viol <= 1'b1;
            state <= S_IDLE;
          end else if (!calc) begin
            // calc went low, reset
            state <= S_IDLE;
          end else begin
            // Perform division for t_cycle cycles
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
              // Division complete for t_cycle cycles - store (quotient - OTF_CMD_BITS)
              min_cycles_for_t_cycle <= quotient > OTF_CMD_BITS ? (quotient - OTF_CMD_BITS) : 0;
              
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
            // n_cs_high_time_calc = max(min_cycles_for_t_conv, min_cycles_for_t_cycle)
            if (min_cycles_for_t_conv < min_cycles_for_t_cycle) begin
              final_result <= min_cycles_for_t_cycle;
            end else begin
              final_result <= min_cycles_for_t_conv;
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
              // Cap n_cs_high_time at 255 (at the maximum 50MHz SPI clock, this plus the command bits is 5420ns, which is over the maximum 4000ns required)
              if (final_result > 255) begin
              n_cs_high_time <= 8'd255;
              end else begin
              n_cs_high_time <= final_result[7:0]; // Truncate to 8 bits
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
