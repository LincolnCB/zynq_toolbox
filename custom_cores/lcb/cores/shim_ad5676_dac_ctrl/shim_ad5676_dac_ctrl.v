`timescale 1 ns / 1 ps

module shim_ad5676_dac_ctrl #(
  parameter ABS_CAL_MAX = 16'd4096 // Maximum absolute calibration value
)(
  input  wire        clk,
  input  wire        resetn,

  input  wire        boot_test_skip, // Skip the boot test sequence

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
  input  wire        miso_resetn,
  input  wire        miso,
  output reg         ldac
);

  // TODO: Make this external and locked when the SPI system is on
  // Minimum time for the n_cs signal to be high (in clock cycles)
  // Calculation: 
  //  - 50 MHz maximum SPI clock frequency
  //  - 830 ns minimum time between n_cs rising edges
  //  - 42 clock cycles needed
  //  - 24 bits per SPI command
  //  - 42 - 24 = 18 clock cycles for n_cs to be high
  //  - Requires a minimum of 3 clock cycles for DAC word loading
  wire [4:0] n_cs_high_time = 5'd18;

  localparam DAC_TEST_CH = 3'd5; // DAC channel for testing (5 is nice for a clear binary value)
  localparam DAC_TEST_VAL = 16'b1000000000001010; // Test value for DAC channel (near midrange is good)

  // DAC SPI command
  localparam SPI_CMD_REG_WRITE = 4'b0001; // DAC SPI command for register write to be later loaded with LDAC
  localparam SPI_CMD_REG_READ  = 4'b1001; // DAC SPI command for register readback

  // States
  localparam S_RESET      = 4'd0; // Reset state
  localparam S_INIT       = 4'd1; // Initialization state, starting a test write to the DAC
  localparam S_TEST_WR    = 4'd2; // Setup -- Write test value
  localparam S_REQ_RD     = 4'd3; // Setup -- Request read of the written test value
  localparam S_TEST_RD    = 4'd4; // Setup -- Read test value
  localparam S_IDLE       = 4'd5; // Idle state, waiting for commands
  localparam S_DELAY      = 4'd6; // Delay state, waiting for delay timer to expire
  localparam S_TRIG_WAIT  = 4'd7; // Trigger wait state, waiting for a trigger signal
  localparam S_DAC_WR     = 4'd8; // DAC write state
  localparam S_ERROR      = 4'd9; // Error state, invalid command or unexpected condition


  // Command types
  localparam CMD_NO_OP   = 2'b00;
  localparam CMD_DAC_WR  = 2'b01;
  localparam CMD_SET_CAL = 2'b10;
  localparam CMD_CANCEL  = 2'b11; // Cancel the delay or trigger wait with no LDAC

  // Command bit positions
  localparam TRIG_BIT = 29; // Bit position for TRIGGER WAIT in the command word
  localparam CONT_BIT = 28; // Bit position for CONTINUE in the command word
  localparam LDAC_BIT = 27; // Bit position for DO LDAC in the command word

  // DAC loading stages -- loads a pair of DAC values from the FIFO in three stages
  localparam DAC_LOAD_STAGE_INIT = 2'b00; // Initial stage, waiting for the first DAC value to be loaded
  localparam DAC_LOAD_STAGE_CAL  = 2'b01; // Second stage, adding calibration and getting absolute values
  localparam DAC_LOAD_STAGE_CONV = 2'b10; // Final conversion stage, converting back to offset representation

  // State and command processing
  reg  [ 3:0] state;
  wire        cmd_done;
  wire        next_cmd;
  wire [ 2:0] next_cmd_state;
  wire        cancel_wait;
  wire        error;
  // Command word toggled bits
  reg         do_ldac;
  reg         wait_for_trig;
  reg         expect_next;
  // Delay timer
  reg  [25:0] delay_timer;
  // Calibration
  reg  signed [15:0] cal_val [0:7]; // Calibration values for each channel
  // DAC MOSI control signals
  reg         read_next_dac_val_pair;
  wire        start_spi_command;
  reg         dac_wr_done;
  wire        last_dac_channel;
  wire        second_dac_channel_of_pair;
  wire        dac_spi_command_done;
  reg  [ 4:0] n_cs_timer;
  reg         running_n_cs_timer; // Flag to indicate if CS timer is running
  wire        cs_wait_done;
  reg  [ 2:0] dac_channel;
  reg  [ 4:0] spi_bit;
  reg  signed [15:0] first_dac_val_signed;
  reg  signed [16:0] first_dac_val_cal_signed;
  reg  signed [15:0] second_dac_val_signed;
  reg  signed [16:0] second_dac_val_cal_signed;
  reg  [47:0] mosi_shift_reg; // Shift register for DAC SPI data
  reg  [14:0] abs_dac_val [0:7]; // Stored absolute DAC values for each channel
  reg  [ 1:0] dac_load_stage;
  // DAC MISO signals
  reg  [14:0] miso_shift_reg; // Shift register for MISO data
  wire [15:0] miso_data;
  reg  [ 3:0] miso_bit; // MISO bit counter
  reg         start_miso_mosi_clk; // Indicate whether to read the MISO data (in MOSI clock domain)
  wire        start_miso; // Indicate whether to read the MISO data
  wire        n_miso_data_ready_mosi_clk; // Indicate whether the MISO data is ready to be read in MOSI clock domain
  wire [15:0] miso_data_mosi_clk; // MISO data in MOSI clock domain
  wire        boot_readback_match; // Indicate whether the readback matches the expected value


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
    if (!resetn)                                                state <= S_RESET; // Reset to initial state
    else if (error)                                             state <= S_ERROR; // Check for error states
    else if (state == S_RESET)                                  state <= boot_test_skip ? S_IDLE : S_INIT; // Skip boot test if requested
    else if (state == S_INIT)                                   state <= S_TEST_WR; // Transition to TEST_WR first in initialization
    else if (state == S_TEST_WR && dac_spi_command_done)        state <= S_REQ_RD; // Transition to REQ_RD after writing test value
    else if (state == S_REQ_RD && dac_spi_command_done)         state <= S_TEST_RD; // Transition to TEST_RD after requesting read
    else if (state == S_TEST_RD && ~n_miso_data_ready_mosi_clk) state <= S_IDLE; // Transition to IDLE after reading test value (mismatch will set error flag)
    else if (cancel_wait)                                       state <= S_IDLE; // Cancel the current wait state if cancel command is received
    else if (cmd_done)                                          state <= next_cmd_state; // Transition to state of next command if command is finished
    else if (state == S_DAC_WR && dac_wr_done)                  state <= wait_for_trig ? S_TRIG_WAIT : S_DELAY; // If the DAC write is done, go to the proper wait state
  end
  // Setup done
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) setup_done <= 1'b0; // Reset setup done on reset or error
    else if (boot_test_skip) setup_done <= 1'b1; // If boot test is skipped, set setup done immediately
    else if ((state == S_TEST_RD) && ~n_miso_data_ready_mosi_clk && boot_readback_match) setup_done <= 1'b1;
  end


  //// Command bits processing
  // do_ldac, wait_for_trig, expect_next
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) begin
      do_ldac <= 1'b0;
      wait_for_trig <= 1'b0;
      expect_next <= 1'b0;
    end else if (next_cmd) begin
      if ((cmd_word[31:30] == CMD_NO_OP ) || (cmd_word[31:30] == CMD_DAC_WR)) begin
        do_ldac <= cmd_word[LDAC_BIT]; // Set do_ldac based on command word
        wait_for_trig <= cmd_word[TRIG_BIT]; // Set wait_for_trig based on command word
        expect_next <= cmd_word[CONT_BIT]; // Set expect_next based on command word
      end else begin
        do_ldac <= 1'b0; // Reset do_ldac if not a NO_OP or DAC_WR command
        wait_for_trig <= 1'b0; // Reset wait_for_trig if not a NO_OP or DAC_WR command
        expect_next <= 1'b0; // Reset expect_next if not a NO_OP or DAC_WR command
      end
    end
  end
  // Command word read enable
  assign cmd_word_rd_en = (state != S_ERROR) && !cmd_buf_empty 
                          && (read_next_dac_val_pair || cmd_done || cancel_wait);


  //// Delay timer
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) delay_timer <= 26'd0;
    // If the next command is a DAC write or no-op with a delay wait, load the delay timer
    else if (next_cmd 
             && ((cmd_word[31:30] == CMD_DAC_WR) || (cmd_word[31:30] == CMD_NO_OP)) 
             && !cmd_word[TRIG_BIT]) delay_timer <= cmd_word[25:0]; // Load delay timer with delay value from command word
    else if (delay_timer > 0) delay_timer <= delay_timer - 1; // Decrement delay timer to zero if nonzero
  end


  //// Errors
  // Error flag
  assign error = (state == S_TEST_RD && ~n_miso_data_ready_mosi_clk && ~boot_readback_match) // Readback mismatch (boot fail)
                 || (state != S_TRIG_WAIT && trigger) // Unexpected trigger
                 || (state == S_DAC_WR && ldac_shared) // Unexpected LDAC assertion
                 || (next_cmd && next_cmd_state == S_ERROR) // Bad command
                 || (((cmd_done && expect_next) || read_next_dac_val_pair) && cmd_buf_empty) // Command buffer underflow
                 || cal_oob // Calibration value out of bounds
                 || dac_val_oob; // DAC value out of bounds
  // Boot check fail
  assign boot_readback_match = (miso_data_mosi_clk == DAC_TEST_VAL); // Readback matches the test value
  always @(posedge clk) begin
    if (!resetn) boot_fail <= 1'b0; // Reset boot fail on reset
    if (state == S_TEST_RD && ~n_miso_data_ready_mosi_clk) boot_fail <= ~boot_readback_match; 
  end
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
    else if (((cmd_done && expect_next) || read_next_dac_val_pair) && cmd_buf_empty) cmd_buf_underflow <= 1'b1; // Underflow if expecting buffer item but buffer is empty
  end
  // DAC val out of bounds
  always @(posedge clk) begin
    if (!resetn) dac_val_oob <= 1'b0; // Reset out of bounds flag on reset
    else begin // Set out of bounds flag if either of the following conditions are met:
      if (dac_load_stage == DAC_LOAD_STAGE_INIT
          && read_next_dac_val_pair && !cmd_buf_empty 
          && (cmd_word[15:0] == 16'hFFFF || cmd_word[31:16] == 16'hFFFF)) dac_val_oob <= 1'b1; // If incoming DAC value is 0xFFFF
      else if (dac_load_stage == DAC_LOAD_STAGE_CONV && 
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

  //// DAC word sequencing
  // DAC channel count status
  assign last_dac_channel = (dac_channel == 3'd7); // Last channel is when all bits are set
  assign second_dac_channel_of_pair = (dac_channel[0] == 1'b1); // Even channel is when the least significant bit is set (off by 1)
  assign dac_spi_command_done = ((state == S_DAC_WR)
                                 || (state == S_TEST_WR)
                                 || (state == S_REQ_RD)
                                 || (state == S_TEST_RD))
                                && !n_cs && !running_n_cs_timer && spi_bit == 0; // SPI command is done when CS is deasserted and SPI bit counter is zero
  // Read next DAC word from command buffer
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) read_next_dac_val_pair <= 1'b0;
    // If next command is DAC write, immediately read next DAC word (two channels)
    else if (next_cmd && cmd_word[31:30] == CMD_DAC_WR) read_next_dac_val_pair <= 1'b1;
    // If done writing to DAC and finished the second channel of the update pair, 
    //   but it's not the last pair, read the next word (pair of channels)
    else if (state == S_DAC_WR
             && dac_spi_command_done
             && second_dac_channel_of_pair 
             && !last_dac_channel) read_next_dac_val_pair <= 1'b1;
    else read_next_dac_val_pair <= 1'b0;
  end
  // DAC write done
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) dac_wr_done <= 1'b0;
    else if (state == S_DAC_WR && dac_spi_command_done && last_dac_channel) dac_wr_done <= 1'b1; // Ready when all channels are written
    else dac_wr_done <= 1'b0; // Not ready otherwise
  end
  // DAC channel index
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) dac_channel <= 3'd0;
    else if (next_cmd && cmd_word[31:30] == CMD_DAC_WR) dac_channel <= 3'd0;
    else if (state == S_DAC_WR && dac_spi_command_done) dac_channel <= dac_channel + 1; // Increment channel when timer is done
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
          if (read_next_dac_val_pair && !cmd_buf_empty) begin
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
          dac_load_stage <= DAC_LOAD_STAGE_INIT; // Conversion is done
        end
      endcase
  end


  //// SPI MOSI control
  // Start the next SPI command
  assign start_spi_command = (next_cmd && cmd_word[31:30] == CMD_DAC_WR) 
                             || (dac_spi_command_done && (state != S_DAC_WR || !last_dac_channel))
                             || (state == S_INIT);
  // ~(Chip Select) timer
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) n_cs_timer <= 5'd0;
    else if (start_spi_command) n_cs_timer <= n_cs_high_time;
    else if (n_cs_timer > 0) n_cs_timer <= n_cs_timer - 1;
    running_n_cs_timer <= (n_cs_timer > 0); // Flag to indicate if CS timer is running
  end
  // ~(Chip Select) (n_cs) has been high for the required time (timer went from nonzero to zero)
  assign cs_wait_done = (running_n_cs_timer && n_cs_timer == 0);
  // ~(Chip Select) (n_cs) signal
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) n_cs <= 1'b1; // Reset n_CS on reset or error
    else if (cs_wait_done) n_cs <= 1'b0; // Assert CS when timer is done
    else if (dac_spi_command_done || state == S_IDLE) n_cs <= 1'b1; // Deassert CS when SPI command is done
  end
  // DAC word SPI bit
  always @(posedge clk) begin
    if (!resetn || state != S_DAC_WR) spi_bit <= 5'd0;
    else if (spi_bit > 0) spi_bit <= spi_bit - 1; // Decrement SPI bit counter
    else if (cs_wait_done) spi_bit <= 5'd23; // Load SPI bit counter with 24 bits when CS is done waiting
  end
  // SPI MOSI bit
  assign mosi = mosi_shift_reg[47]; // MOSI is the most significant bit of the shift register
  // SPI MOSI shift register
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) mosi_shift_reg <= 48'd0; // Reset shift register on reset or error
    else if (spi_bit > 0) mosi_shift_reg <= {mosi_shift_reg[46:0], 1'b0}; // Shift bits out
    else if (state == S_INIT) begin // If just exiting reset:
      // Load the shift register with the test value for boot-up sequence
      mosi_shift_reg <= {spi_write_cmd(DAC_TEST_CH, DAC_TEST_VAL), 24'b0}; // Load test value for test channel
    end else if (state == S_TEST_WR && dac_spi_command_done) begin // If finished with the test write:
      // Load the shift register with the read request and a write to reset the test value
      mosi_shift_reg <= {spi_read_cmd(DAC_TEST_CH), spi_write_cmd(3'b101, {1'b1, 15'b0})}; // Read test channel and write midrange to reset test value
    end else if (state == S_DAC_WR && dac_load_stage == DAC_LOAD_STAGE_CONV) begin
      // Load the shift register with the first DAC value and the second DAC value
      mosi_shift_reg <= {spi_write_cmd(dac_channel, signed_to_offset(first_dac_val_cal_signed)), 
                        spi_write_cmd(dac_channel + 1, signed_to_offset(second_dac_val_cal_signed))};
    end
  end
  // Start MISO read in MOSI clock domain (should show up 1 cycle later on readback MISO clock than equivalent MOSI clock cycle)
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) start_miso_mosi_clk <= 1'b0; // Reset start MISO read signal on reset or error
    else if (state == S_TEST_RD && spi_bit == 5'd16) start_miso_mosi_clk <= 1'b1;
    else start_miso_mosi_clk <= 1'b0;
  end

  //// SPI MISO control
  // Start MISO synchonization
  sync_incoherent start_miso_sync(
    .clk(miso_sck), // MISO clock
    .resetn(miso_resetn), // Reset for MISO clock domain
    .din(start_miso_mosi_clk), // Start MISO read signal in MOSI clock domain
    .dout(start_miso) // Start MISO read signal in MISO clock domain
  );
  // MISO FIFO
  fifo_async #(
    .DATA_WIDTH  (16), // MISO data width
    .ADDR_WIDTH  (2) // FIFO address width (4 entries)
  ) miso_fifo (
    .wr_clk      (miso_sck), // MISO clock
    .wr_rst_n    (miso_resetn), // Reset for MISO clock domain
    .wr_data     (miso_data), // MISO data to write
    .wr_en       (miso_bit == 4'd1), // Write MISO data when the bit counter is 1 (last bit is being read)

    .rd_clk      (clk), // FPGA SCK
    .rd_rst_n    (resetn),
    .rd_data     (miso_data_mosi_clk),
    .rd_en       (~n_miso_data_ready_mosi_clk), // Immediately read MISO data when available in the MOSI clock domain
    .empty       (n_miso_data_ready_mosi_clk)
  );
  // MISO bit counter
  always @(posedge miso_sck) begin
    if (!miso_resetn) miso_bit <= 4'd0; // Reset MISO bit counter on reset
    else if (miso_bit > 0) miso_bit <= miso_bit - 1; // Decrement MISO bit counter
    else if (start_miso) miso_bit <= 4'd15; // Load MISO bit counter with 16 bits when starting MISO read
  end
  // MISO shift register
  always @(posedge miso_sck) begin
    if (!miso_resetn) miso_shift_reg <= 15'd0;
    else if (miso_bit > 1) miso_shift_reg <= {miso_shift_reg[13:0], miso}; // Shift MISO data into the shift register
    else if (start_miso) miso_shift_reg <= {14'd0, miso}; // Start MISO read
  end
  assign miso_data = {miso_shift_reg, miso}; // MISO data is the shift register with the last bit from MISO

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
  // SPI command to read from particular DAC channel on MISO during the next SPI word
  function [23:0] spi_read_cmd(input [2:0] channel);
    spi_read_cmd = {SPI_CMD_REG_READ, 1'b0, channel, 16'b0}; // Construct the SPI command with read command and channel
  endfunction

endmodule
