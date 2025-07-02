`timescale 1 ns / 1 ps

module shim_ad5676_dac_ctrl #(
  parameter ABS_CAL_MAX = 16'd4096 // Maximum absolute calibration value
)(
  input  wire        clk,
  input  wire        resetn,

  output reg         setup_done,

  output wire        cmd_word_rd_en,
  input  wire [31:0] cmd_word,
  input  wire        cmd_buf_empty,

  input  wire        trigger,
  input  wire        ldac_shared,
  output wire        waiting_for_trig,

  output reg         boot_fail,
  output reg         cmd_buf_underflow,
  output reg         unexp_trig,
  output reg         bad_cmd,
  output reg         cal_oob,
  output reg         dac_val_oob,
  
  output reg [119:0] abs_dac_val_concat,

  output reg         n_cs,
  output wire        mosi,
  input  wire        miso_sck,
  input  wire        miso,
  output reg         ldac
);

  // Internal constants
  localparam DAC_WORD_MIN_TIME = 6'd41; // Minimum DAC delay clock cycles (minus 1)
  localparam DAC_SPI_START_DELAY = 6'd7; // Delay after starting DAC write cycle to start the SPI transfer (1-15 max)
  localparam DAC_SPI_START_TIME = DAC_WORD_MIN_TIME - DAC_SPI_START_DELAY;

  // DAC SPI command
  localparam SPI_CMD_REG_WRITE = 4'b0001; // DAC SPI command for register write to be later loaded with LDAC

  // States
  localparam S_INIT      = 3'd0; // Initial state
  localparam S_IDLE      = 3'd1; // Idle state, waiting for commands
  localparam S_DELAY     = 3'd2; // Delay state, waiting for delay timer to expire
  localparam S_TRIG_WAIT = 3'd3; // Waiting for trigger state
  localparam S_DAC_WR    = 3'd4; // DAC write state
  localparam S_ERROR     = 3'd5; // Error state, invalid command or unexpected condition

  // Command types
  localparam CMD_NO_OP   = 2'b00;
  localparam CMD_DAC_WR  = 2'b01;
  localparam CMD_SET_CAL = 2'b10;
  localparam CMD_CANCEL  = 2'b11; // Cancel the delay or trigger wait with no LDAC

  // Command bit positions
  localparam TRIG_BIT = 29; // Bit position for TRIGGER WAIT in the command word
  localparam CONT_BIT = 28; // Bit position for CONTINUE in the command word
  localparam LDAC_BIT = 27; // Bit position for DO LDAC in the command word

  // DAC loading stages
  localparam DAC_LOAD_STAGE_INIT = 2'b00; // Initial stage, waiting for the first DAC value to be loaded
  localparam DAC_LOAD_STAGE_CAL  = 2'b01; // Second stage, adding calibration and getting absolute values
  localparam DAC_LOAD_STAGE_CONV = 2'b10; // Final conversion stage, converting back to offset representation

  // State and command processing
  reg  [ 2:0] state;
  wire        cmd_done;
  wire        next_cmd;
  wire [ 2:0] next_cmd_state;
  wire        cancel_wait;
  // Command word toggled bits
  reg         do_ldac;
  reg         wait_for_trig;
  reg         expect_next;
  // Delay timer
  reg  [24:0] delay_timer;
  // Calibration
  reg  signed [15:0] cal_val [0:7]; // Calibration values for each channel
  // DAC control signals
  reg         read_next_dac_word;
  wire        write_next_spi_word;
  reg         dac_wr_done;
  reg  [ 5:0] dac_update_timer;
  reg  [ 2:0] dac_channel;
  wire        last_dac_channel;
  wire        odd_dac_channel;
  reg  [ 4:0] spi_bit;
  reg  signed [15:0] first_dac_val_signed;
  reg  signed [16:0] first_dac_val_cal_signed;
  reg  signed [15:0] second_dac_val_signed;
  reg  signed [16:0] second_dac_val_cal_signed;
  reg  [47:0] dac_shift_reg; // Shift register for DAC SPI data
  reg  [14:0] abs_dac_val [0:7]; // Stored absolute DAC values for each channel
  reg  [ 1:0] dac_load_stage;


  //// State machine transitions
  // Allows a cancel command to cancel a delay or trigger wait
  assign cancel_wait =  (state == S_DELAY || state == S_TRIG_WAIT || (state == S_DAC_WR && dac_wr_done))
                        && !cmd_buf_empty 
                        && cmd_word[31:30] == CMD_CANCEL;
  // Current command is finished
  assign cmd_done = (state == S_IDLE && !cmd_buf_empty) 
                    || (state == S_DELAY && delay_timer == 0)
                    || (state == S_TRIG_WAIT && trigger)
                    || (state == S_DAC_WR && dac_wr_done && !wait_for_trig && delay_timer == 0);
  assign next_cmd = cmd_done && !cmd_buf_empty;
  // Next state from upcoming command
  assign next_cmd_state =  cmd_buf_empty ? (expect_next ? S_ERROR : S_IDLE) // If buffer is empty, error if expecting next command, otherwise IDLE
                           : (cmd_word[31:30] == CMD_NO_OP) ? (cmd_word[TRIG_BIT] ? S_TRIG_WAIT : S_DELAY) // If command is NO_OP, either wait for trigger or delay depending on TRIG_BIT
                           : (cmd_word[31:30] == CMD_DAC_WR) ? S_DAC_WR // If command is DAC write, go to DAC_WR state
                           : (cmd_word[31:30] == CMD_SET_CAL) ? S_IDLE // If command is SET_CAL, go to IDLE
                           : (cmd_word[31:30] == CMD_CANCEL) ? S_IDLE // If command is CANCEL, go to IDLE 
                           : S_ERROR; // If command is not recognized, go to ERROR state
  // Waiting for trigger flag
  assign waiting_for_trig = (state == S_TRIG_WAIT);
  // State transition
  always @(posedge clk) begin
    if (!resetn)                                  state <= S_INIT; // Reset to initial state
    else if (state == S_INIT)                     state <= S_IDLE; // Transition from INIT to IDLE
    else if (cal_oob)                             state <= S_ERROR; // Error if calibration value is out of bounds
    else if (trigger && !waiting_for_trig)        state <= S_ERROR; // Error if trigger occurs when not waiting for one
    else if (ldac_shared && state == S_DAC_WR)    state <= S_ERROR; // Error if global LDAC is asserted while this DAC is writing
    else if (read_next_dac_word && cmd_buf_empty) state <= S_ERROR; // Error if DAC sample is expected but buffer is empty
    else if (cmd_buf_underflow)                   state <= S_ERROR; // Error if command buffer underflows
    else if (cancel_wait)                         state <= S_IDLE; // Cancel the current wait state if cancel command is received
    else if (cmd_done)                            state <= next_cmd_state; // Transition to state of next command if command is finished
    else if (state == S_DAC_WR && dac_wr_done)    state <= wait_for_trig ? S_TRIG_WAIT : S_DELAY; // If the DAC write is done, go to the proper wait state
    else if (state == S_DAC_WR && dac_val_oob)    state <= S_ERROR; // Error if calibrated DAC value is out of bounds
    else state <= state; // Stay in the same state if no conditions are met
  end
  // Setup done
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) setup_done <= 1'b0; // Reset setup done on reset or error
    else if (state == S_INIT) setup_done <= 1'b1; // Set setup done when entering INIT state
  end


  //// Command bits processing
  // do_ldac, wait_for_trig, expect_next
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) begin
      do_ldac <= 1'b0;
      wait_for_trig <= 1'b0;
      expect_next <= 1'b0;
    end else if (next_cmd && ((cmd_word[31:30] == CMD_NO_OP ) || (cmd_word[31:30] == CMD_DAC_WR))) begin
      do_ldac <= cmd_word[LDAC_BIT]; // Set do_ldac based on command word
      wait_for_trig <= cmd_word[TRIG_BIT]; // Set wait_for_trig based on command word
      expect_next <= cmd_word[CONT_BIT]; // Set expect_next based on command word
    end
  end
  // Command word read enable
  assign cmd_word_rd_en = (state != S_ERROR) && !cmd_buf_empty 
                          && (read_next_dac_word || cmd_done || cancel_wait);


  //// Delay timer
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) delay_timer <= 25'd0;
    // If the next command is a DAC write or no-op with a delay wait, load the delay timer
    else if (next_cmd 
             && ((cmd_word[31:30] == CMD_DAC_WR) || (cmd_word[31:30] == CMD_NO_OP)) 
             && !cmd_word[TRIG_BIT]) delay_timer <= cmd_word[24:0]; // Load delay timer with delay value from command word
    else if (delay_timer > 0) delay_timer <= delay_timer - 1; // Decrement delay timer to zero if nonzero
  end


  //// Errors
  // Unexpected trigger
  always @(posedge clk) begin
    if (!resetn) unexp_trig <= 1'b0;
    else if (state != S_TRIG_WAIT && trigger) unexp_trig <= 1'b1; // Unexpected trigger if triggered while not waiting for one
    else if (state == S_DAC_WR && ldac_shared) unexp_trig <= 1'b1; // Unexpected trigger if global LDAC is asserted while writing
  end
  // Bad command
  always @(posedge clk) begin
    if (!resetn) bad_cmd <= 1'b0;
    else if (next_cmd && next_cmd_state == S_ERROR) bad_cmd <= 1'b1; // Bad command if next command is parsed as ERROR
  end
  // Command buffer underflow
  always @(posedge clk) begin
    if (!resetn) cmd_buf_underflow <= 1'b0;
    else if (((cmd_done && expect_next) || read_next_dac_word) && cmd_buf_empty) cmd_buf_underflow <= 1'b1; // Underflow if expecting buffer item but buffer is empty
  end
  // DAC val out of bounds
  always @(posedge clk) begin
    if (!resetn) dac_val_oob <= 1'b0; // Reset out of bounds flag on reset
    else begin // Set out of bounds flag if either of the following conditions are met:
      if (dac_load_stage == 2'b00
          && read_next_dac_word && !cmd_buf_empty 
          && (cmd_word[15:0] == 16'hFFFF || cmd_word[31:16] == 16'hFFFF)) dac_val_oob <= 1'b1; // If incoming DAC value is 0xFFFF
      else if (dac_load_stage == 2'b10 && 
               (first_dac_val_cal_signed < -16'sd32767 || first_dac_val_cal_signed > 16'sd32767 ||
                second_dac_val_cal_signed < -16'sd32767 || second_dac_val_cal_signed > 16'sd32767)) dac_val_oob <= 1'b1; // If calibrated DAC value is out of bounds
    end
  end
  

  //// DAC updating
  // LDAC activation
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) ldac <= 1'b0;
    else if (do_ldac && cmd_done && !cancel_wait) begin
      ldac <= 1'b1; // If do_ldac is set, activate LDAC at the end of the command (except for IDLE)
    end
    else ldac <= 1'b0; // Otherwise, deactivate LDAC
  end
  // Update absolute DAC values concatenation
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) abs_dac_val_concat <= 120'd0; // Reset concatenation on reset or error
    else if (ldac) begin
      // Concatenate absolute DAC values when LDAC is asserted
      abs_dac_val_concat <= {abs_dac_val[7], abs_dac_val[6], abs_dac_val[5], 
                             abs_dac_val[4], abs_dac_val[3], abs_dac_val[2], 
                             abs_dac_val[1], abs_dac_val[0]};
    end
  end
      


  //// Calibration
  // Calibration value set and out-of-bounds
  always @(posedge clk) begin
    if (!resetn) begin
      cal_val[0] <= 16'd0;
      cal_val[1] <= 16'd0;
      cal_val[2] <= 16'd0;
      cal_val[3] <= 16'd0;
      cal_val[4] <= 16'd0;
      cal_val[5] <= 16'd0;
      cal_val[6] <= 16'd0;
      cal_val[7] <= 16'd0;
      cal_oob <= 1'b0;
    end else if (next_cmd && cmd_word[31:30] == CMD_SET_CAL) begin
      if ($signed(cmd_word[15:0]) <= $signed(ABS_CAL_MAX) && $signed(cmd_word[15:0]) >= -$signed(ABS_CAL_MAX)) begin
        cal_val[cmd_word[18:16]] <= cmd_word[15:0]; // Set calibration value for the channel if within bounds
      end else begin
        cal_oob <= 1'b1; // Set out-of-bounds flag if calibration value is out of range
      end
    end
  end

  //// DAC boot-up SPI sequence
  // TODO: Implement boot-up sequence
  always @(posedge clk) begin
    if (!resetn) boot_fail <= 1'b0; // Reset boot fail on reset
  end

  //// DAC word sequencing
  // DAC channel count status
  assign last_dac_channel = (dac_channel == 3'd7); // Last channel is when all bits are set
  assign even_dac_channel = (dac_channel[0] == 1'b1); // Even channel is when the least significant bit is set (off by 1)
  // Read next DAC word from command buffer
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) read_next_dac_word <= 1'b0;
    // If next command is DAC write, immediately read next DAC word (two channels)
    else if (next_cmd && cmd_word[31:30] == CMD_DAC_WR) read_next_dac_word <= 1'b1;
    // If writing to DAC and finished the second channel (every other, but not on ch 7), read the next word (two channels)
    else if (state == S_DAC_WR && even_dac_channel && !last_dac_channel && dac_update_timer == 0) read_next_dac_word <= 1'b1;
    else read_next_dac_word <= 1'b0;
  end
  // DAC word timer
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) dac_update_timer <= 6'd0;
    else if (next_cmd && cmd_word[31:30] == CMD_DAC_WR) dac_update_timer <= DAC_WORD_MIN_TIME;
    else if (state == S_DAC_WR && dac_update_timer == 0 && !last_dac_channel) dac_update_timer <= DAC_WORD_MIN_TIME;
    else if (state == S_DAC_WR && dac_update_timer > 0) dac_update_timer <= dac_update_timer - 1;
  end
  // DAC write done
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) dac_wr_done <= 1'b0;
    else if (state == S_DAC_WR && dac_update_timer == 0 && last_dac_channel) dac_wr_done <= 1'b1; // Ready when all channels are written
    else dac_wr_done <= 1'b0; // Not ready otherwise
  end
  // DAC channel index
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) dac_channel <= 3'd0;
    else if (next_cmd && cmd_word[31:30] == CMD_DAC_WR) dac_channel <= 3'd0;
    else if (state == S_DAC_WR && dac_update_timer == 0) dac_channel <= dac_channel + 1; // Increment channel when timer is done
  end
  // DAC value loading
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) begin
      first_dac_val_signed <= 16'd0;
      first_dac_val_cal_signed <= 17'd0;
      second_dac_val_signed <= 16'd0;
      second_dac_val_cal_signed <= 17'd0;
      abs_dac_val[0] <= 15'd0;
      abs_dac_val[1] <= 15'd0;
      abs_dac_val[2] <= 15'd0;
      abs_dac_val[3] <= 15'd0;
      abs_dac_val[4] <= 15'd0;
      abs_dac_val[5] <= 15'd0;
      abs_dac_val[6] <= 15'd0;
      abs_dac_val[7] <= 15'd0;
      dac_load_stage <= DAC_LOAD_STAGE_INIT; // Reset DAC load stage
    end else 
      case (dac_load_stage)
        DAC_LOAD_STAGE_INIT: begin // Initial stage, waiting for the first DAC value to be loaded
          if (read_next_dac_word && !cmd_buf_empty) begin
            // Reject DAC value of 0xFFFF
            if (!(cmd_word[15:0] == 16'hFFFF || cmd_word[31:16] == 16'hFFFF))  begin
              first_dac_val_signed <= offset_to_signed(cmd_word[15:0]); // Load first DAC value from command word
              second_dac_val_signed <= offset_to_signed(cmd_word[31:16]); // Load second DAC value from command word
              dac_load_stage <= DAC_LOAD_STAGE_CAL; // Move to next stage
            end
          end
        end
        DAC_LOAD_STAGE_CAL: begin // Second stage, adding calibration and getting absolute values
          first_dac_val_cal_signed <= first_dac_val_signed + cal_val[dac_channel]; // Add calibration to first DAC value
          second_dac_val_cal_signed <= second_dac_val_signed + cal_val[dac_channel+1]; // Add calibration to second DAC value
          abs_dac_val[dac_channel] <= signed_to_abs(first_dac_val_cal_signed); // Convert first DAC value to absolute
          abs_dac_val[dac_channel + 1] <= signed_to_abs(second_dac_val_cal_signed); // Convert second DAC value to absolute
          dac_load_stage <= DAC_LOAD_STAGE_CONV; // Move to final stage
        end
        DAC_LOAD_STAGE_CONV: begin // Final conversion stage, converting to offset representation
          // Logic is handled in the SPI MOSI control shift register
          // OOB is checked in the DAC val out of bounds section
          dac_load_stage <= 2'b00; // Conversion is done
        end
      endcase
  end


  //// SPI MOSI control
  // Write next SPI word signal
  assign write_next_spi_word = (state == S_DAC_WR && dac_update_timer == DAC_SPI_START_TIME);
  // DAC word SPI bit
  always @(posedge clk) begin
    if (!resetn || state != S_DAC_WR) spi_bit <= 5'd0;
    else if (spi_bit > 0) spi_bit <= spi_bit - 1; // Decrement SPI bit counter
    else if (write_next_spi_word) spi_bit <= 5'd23;
  end
  // n_CS signal
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) n_cs <= 1'b1; // Reset n_CS on reset or error
    else if (write_next_spi_word) n_cs <= 1'b0; // Assert CS when writing to DAC
    else if (spi_bit == 0) n_cs <= 1'b1; // Deassert CS when not writing or done with SPI bits
  end
  // SPI MOSI bit
  assign mosi = dac_shift_reg[47]; // MOSI is the most significant bit of the shift register
  // SPI MOSI shift register
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) dac_shift_reg <= 48'd0; // Reset shift register on reset or error
    else if (spi_bit > 0) dac_shift_reg <= {dac_shift_reg[46:0], 1'b0}; // Shift bits out
    else if (state == S_DAC_WR && dac_load_stage == 2'b10) begin
      // Load the shift register with the first DAC value and the second DAC value
      dac_shift_reg <= {spi_write_cmd(dac_channel, signed_to_offset(first_dac_val_cal_signed)), 
                        spi_write_cmd(dac_channel + 1, signed_to_offset(second_dac_val_cal_signed))};
    end
  end

  //// SPI MISO control
  // TODO: Handle MISO readback

  //// Functions for conversions
  // Convert from offset to signed     
  // Given a 16-bit 0-65535 number, treat 32767 as 0, 0 as -32767, 
  //   and 65535 as disallowed (return 0, handle the error before calling)
  function signed [15:0] offset_to_signed(input [15:0] raw_dac_val);
    begin
      if (raw_dac_val == 16'hFFFF) offset_to_signed = 16'sd0; // Disallowed value, return 0
      else offset_to_signed = $signed(raw_dac_val) - 16'sd32767; // Correct conversion for full 16-bit range
    end
  endfunction
  // Convert the signed value to absolute value
  function [14:0] signed_to_abs(input signed [15:0] signed_val);
    begin
      if (signed_val < 0) begin
        signed_to_abs = -signed_val; // If negative, take the absolute value
      end else begin
        signed_to_abs = signed_val; // If positive, keep the value as is
      end
    end
  endfunction
  // Convert signed value to offset (0-65535) representation
  // Inverse of offset_to_signed: offset = signed_val + 32767
  //   Should handle out of bounds before calling, but will return 32767 if out of bounds
  function [15:0] signed_to_offset(input signed [16:0] signed_val);
    begin
      if (signed_val < -16'sd32767 || signed_val > 16'sd32767) signed_to_offset = 16'd32767; // If out of bounds, return offset representation of 0
      else signed_to_offset = signed_val + 16'sd32767;
    end
  endfunction
  // SPI command to write to particular DAC channel, waiting for LDAC
  function [23:0] spi_write_cmd(input [2:0] channel, input [15:0] dac_val);
    spi_write_cmd = {SPI_CMD_REG_WRITE, 1'b0, channel, dac_val}; // Construct the SPI command with write command and channel
  endfunction

endmodule
