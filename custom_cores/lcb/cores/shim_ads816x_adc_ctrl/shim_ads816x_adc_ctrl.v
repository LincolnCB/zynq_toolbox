module shim_ads816x_adc_ctrl #(
  parameter ADS_MODEL_ID = 8 // 8 for ADS8168, 7 for ADS8167, 6 for ADS8166
)(
  input  wire        clk,
  input  wire        resetn,

  output reg         setup_done,

  output wire        cmd_word_rd_en,
  input  wire [31:0] cmd_word,
  input  wire        cmd_buf_empty,

  output wire        data_word_wr_en,
  output wire [31:0] data_word,
  input  wire        data_buf_full,

  input  wire        trigger,
  output wire        waiting_for_trig,

  output reg         boot_fail,
  output reg         cmd_buf_underflow,
  output reg         data_buf_overflow,
  output reg         unexp_trig,
  output reg         bad_cmd,

  output reg         n_cs,
  output wire        mosi,
  input  wire        miso_sck,
  input  wire        miso_resetn,
  input  wire        miso
);

  // TODO: Make this external and locked when the SPI system is on
  // Minimum time for n_cs signal to be high (in clock cycles)
  // Calculation (different for each ADC model):
  //  - 50 MHz maximum SPI clock frequency
  //  - There's a hard minimum time for n_cs to be high to convert
  //    t_conv = 
  //      -  660 ns for ADS8168
  //      - 1200 ns for ADS8167
  //      - 2500 ns for ADS8166
  //  - Cycles to hit t_conv:
  //      -  33 cycles for ADS8168
  //      -  60 cycles for ADS8167
  //      - 125 cycles for ADS8166
  //  - Minimum time between n_cs rising edges
  //    t_cycle =
  //      -  1 us for ADS8168
  //      -  2 us for ADS8167
  //      -  4 us for ADS8166
  //  - Cycles to hit t_cycle:
  //      -  50 cycles for ADS8168
  //      - 100 cycles for ADS8167
  //      - 200 cycles for ADS8166
  //  - 16 bits per on-the-fly SPI command (the ones we care do sampling with)
  //  - n_cs must be high for the maximum of (n_conv, n_cycle - 16):
  //      - ADS8168: max(33, 50 - 16) = max(33, 34) = 34 cycles
  //      - ADS8167: max(60, 100 - 16) = max(60, 84) = 84 cycles
  //      - ADS8166: max(125, 200 - 16) = max(125, 184) = 184 cycles
  // Set n_cs_high_time based on ADS_MODEL_ID
  wire [ 8:0] n_cs_high_time = 
    (ADS_MODEL_ID == 8) ? 8'd34 :    // ADS8168
    (ADS_MODEL_ID == 7) ? 8'd84 :    // ADS8167
    (ADS_MODEL_ID == 6) ? 8'd184 :   // ADS8166
    8'd184;                          // Default to ADS8166

  // ADC SPI commands
  localparam SPI_CMD_REG_WRITE = 5'b00001;
  localparam SPI_CMD_REG_READ  = 5'b00010;
  localparam ADDR_OTF_CFG = 11'h2A; // On-The-Fly configuration register
  localparam SET_OTF_CFG_DATA = 8'h01; // Set On-The-Fly mode bit in the OTF configuration register

  // States
  localparam S_RESET     = 4'd0; // Reset state
  localparam S_INIT      = 4'd1; // Initialization state, starting a read/write check to the ADC
  localparam S_TEST_WR   = 4'd2; // Setup -- Write first command (set On-The-Fly mode)
  localparam S_REQ_RD    = 4'd3; // Setup -- Request read of the On-The-Fly mode register
  localparam S_TEST_RD   = 4'd4; // Setup -- Read the On-The-Fly mode register
  localparam S_IDLE      = 4'd5; // Idle state, waiting for commands
  localparam S_DELAY     = 4'd6; // Delay state, waiting for delay timer to expire
  localparam S_TRIG_WAIT = 4'd7; // Trigger wait state, waiting for a trigger signal
  localparam S_ADC_RD    = 4'd8; // ADC read state, reading samples from the ADC
  localparam S_ERROR     = 4'd9; // Error state, invalid command or unexpected condition

  // Command types
  localparam CMD_NO_OP   = 2'b00;
  localparam CMD_ADC_RD  = 2'b01;
  localparam CMD_SET_ORD = 2'b10;
  localparam CMD_CANCEL  = 2'b11;

  localparam TRIG_BIT = 29;
  localparam CONT_BIT = 28;

  // State and command processing
  reg  [ 3:0] state;
  wire        cmd_done;
  wire        next_cmd;
  wire [ 2:0] next_cmd_state;
  wire        cancel_wait;
  wire        error;
  // Command word toggled bits
  reg         wait_for_trig;
  reg         expect_next;
  // Delay timer
  reg  [25:0] delay_timer;
  // Sample order for ADC
  reg  [ 2:0] sample_order [0:7];
  // ADC control signals
  wire        start_spi_command;
  reg         adc_rd_done;
  wire        last_adc_word;
  wire        adc_spi_command_done;
  reg  [ 7:0] n_cs_timer;
  reg         running_n_cs_timer;
  wire        cs_wait_done;
  reg  [ 3:0] adc_word_idx;
  reg  [ 4:0] spi_bit;
  reg  [23:0] mosi_shift_reg;
  // ADC MISO signals
  reg  [14:0] miso_shift_reg; // MISO shift register for reading ADC data
  wire [15:0] miso_data; // MISO data output
  reg  [ 3:0] miso_bit; // MISO bit counter
  reg         start_miso_mosi_clk; // Indicate whether to read the MISO data (in MOSI clock domain)
  wire        start_miso; // Indicate whether to read the MISO data
  wire        n_miso_data_ready_mosi_clk; // Indicate whether the MISO data is ready to be read in MOSI clock domain
  wire [15:0] miso_data_mosi_clk; // MISO data in MOSI clock domain
  wire        boot_readback_match; // Indicate whether the readback matches the expected value
  reg  [15:0] miso_data_storage; // Store one 16-bit MISO word before writing to the data buffer
  reg         miso_stored; // Indicate whether the MISO data has been stored
  wire        try_data_write;

  //// State machine transitions
  // Allows a cancel command to cancel a delay or trigger wait
  assign cancel_wait = (state == S_DELAY || state == S_TRIG_WAIT || (state == S_ADC_RD && adc_rd_done))
                        && !cmd_buf_empty
                        && cmd_word[31:30] == CMD_CANCEL;
  // Current command is finished
  assign cmd_done = (state == S_IDLE && !cmd_buf_empty)
                    || (state == S_DELAY && delay_timer == 0)
                    || (state == S_TRIG_WAIT && trigger)
                    || (state == S_ADC_RD && adc_rd_done && !wait_for_trig && delay_timer == 0);
  assign next_cmd = cmd_done && !cmd_buf_empty;
  // Next state from upcoming command
  assign next_cmd_state = cmd_buf_empty ? (expect_next ? S_ERROR : S_IDLE) // If buffer is empty, error if expecting next command, otherwise IDLE
                           : (cmd_word[31:30] == CMD_NO_OP) ? (cmd_word[TRIG_BIT] ? S_TRIG_WAIT : S_DELAY) // If command is NO_OP, either wait for trigger or delay depending on TRIG_BIT
                           : (cmd_word[31:30] == CMD_ADC_RD) ? S_ADC_RD // If command is ADC read, go to ADC read state
                           : (cmd_word[31:30] == CMD_SET_ORD) ? S_IDLE // If command is SET_ORD, go to IDLE
                           : (cmd_word[31:30] == CMD_CANCEL) ? S_IDLE // If command is CANCEL, go to IDLE
                           : S_ERROR; // If command is unrecognized, go to ERROR state
  // Signal indicating the core is waiting for a trigger
  assign waiting_for_trig = (state == S_TRIG_WAIT);
  // State transition
  always @(posedge clk) begin
    if (!resetn)                                                state <= S_RESET; // Reset to initial state
    else if (error)                                             state <= S_ERROR; // Check for error states
    else if (state == S_RESET)                                  state <= S_INIT; // Start the setup initialization
    else if (state == S_INIT)                                   state <= S_TEST_WR; // Transition to TEST_WR first in initialization
    else if (state == S_TEST_WR && adc_spi_command_done)        state <= S_REQ_RD; // Transition to REQ_RD after writing test value
    else if (state == S_REQ_RD && adc_spi_command_done)         state <= S_TEST_RD; // Transition to TEST_RD after requesting read
    else if (state == S_TEST_RD && ~n_miso_data_ready_mosi_clk) state <= S_IDLE; // Transition to IDLE after reading test value (mismatch will set error flag)
    else if (cancel_wait)                                       state <= S_IDLE; // Cancel the current wait state if cancel command is received
    else if (cmd_done)                                          state <= next_cmd_state; // Transition to state of next command if command is finished
    else if (state == S_ADC_RD && adc_rd_done)                  state <= wait_for_trig ? S_TRIG_WAIT : S_DELAY; // If the ADC read is done, go to the proper wait state
  end
  // Setup done
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) setup_done <= 1'b0;
    else if ((state == S_TEST_RD) && ~n_miso_data_ready_mosi_clk && boot_readback_match) setup_done <= 1'b1;
  end

  //// Command bits processing
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) begin
      wait_for_trig <= 1'b0;
      expect_next <= 1'b0;
    end else if (next_cmd) begin
      if ((cmd_word[31:30] == CMD_NO_OP) || (cmd_word[31:30] == CMD_ADC_RD)) begin
        wait_for_trig <= cmd_word[TRIG_BIT];
        expect_next <= cmd_word[CONT_BIT];
      end else begin
        wait_for_trig <= 1'b0; // No wait for trigger for SET_ORD or CANCEL commands
        expect_next <= 1'b0; // No expectation for next command for SET_ORD or CANCEL commands
      end
    end
  end
  // Command word read enable
  assign cmd_word_rd_en = (state != S_ERROR) && !cmd_buf_empty
                          && (cmd_done || cancel_wait);

  // Delay timer
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) delay_timer <= 26'd0;
    else if (next_cmd
             && ((cmd_word[31:30] == CMD_ADC_RD) || (cmd_word[31:30] == CMD_NO_OP))
             && !cmd_word[TRIG_BIT]) delay_timer <= cmd_word[25:0];
    else if (delay_timer > 0) delay_timer <= delay_timer - 1;
  end

  //// Errors
  // Error flag
  assign error = (state == S_TEST_RD && ~n_miso_data_ready_mosi_clk && ~boot_readback_match) // Readback mismatch (boot fail)
                 || (state != S_TRIG_WAIT && trigger)
                 || (next_cmd && next_cmd_state == S_ERROR)
                 || (cmd_done && expect_next && cmd_buf_empty)
                 || (try_data_write && data_buf_full);
  // Boot check fail
  assign boot_readback_match = (miso_data_mosi_clk[15:8] == SET_OTF_CFG_DATA); // Readback matches the test value
  always @(posedge clk) begin
    if (!resetn) boot_fail <= 1'b0; // Reset boot fail on reset
    if (state == S_TEST_RD && ~n_miso_data_ready_mosi_clk) boot_fail <= ~boot_readback_match; 
  end
  // Unexpected trigger
  always @(posedge clk) begin
    if (!resetn) unexp_trig <= 1'b0;
    else if (state != S_TRIG_WAIT && trigger) unexp_trig <= 1'b1;
  end
  // Bad command
  always @(posedge clk) begin
    if (!resetn) bad_cmd <= 1'b0;
    else if (next_cmd && next_cmd_state == S_ERROR) bad_cmd <= 1'b1;
  end
  // Command buffer underflow
  always @(posedge clk) begin
    if (!resetn) cmd_buf_underflow <= 1'b0;
    else if (cmd_done && expect_next && cmd_buf_empty) cmd_buf_underflow <= 1'b1;
  end
  // Data buffer overflow
  always @(posedge clk) begin
    if (!resetn) data_buf_overflow <= 1'b0;
    else if (try_data_write && data_buf_full) data_buf_overflow <= 1'b1;
  end

  //// Sample order
  // Set the sample order with the CMD_SET_ORD command
  integer i;
  always @(posedge clk) begin
    if (!resetn) begin
      for (i = 0; i < 8; i = i + 1)
        sample_order[i] <= i[2:0];
    end else if (next_cmd && cmd_word[31:30] == CMD_SET_ORD) begin
      sample_order[0] <= cmd_word[2:0];
      sample_order[1] <= cmd_word[5:3];
      sample_order[2] <= cmd_word[8:6];
      sample_order[3] <= cmd_word[11:9];
      sample_order[4] <= cmd_word[14:12];
      sample_order[5] <= cmd_word[17:15];
      sample_order[6] <= cmd_word[20:18];
      sample_order[7] <= cmd_word[23:21];
    end
  end

  //// ADC word sequencing
  // ADC word count status (read comes in one cycle after write, so you need 8 + 1 = 9 words)
  assign last_adc_word = (adc_word_idx == 8);
  assign adc_spi_command_done = ((state == S_ADC_RD)
                                 || (state == S_TEST_WR)
                                 || (state == S_REQ_RD)
                                 || (state == S_TEST_RD))
                                && !n_cs && !running_n_cs_timer && spi_bit == 0;
  // ADC done signal
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) adc_rd_done <= 1'b0;
    else if (state == S_ADC_RD && adc_spi_command_done && last_adc_word) adc_rd_done <= 1'b1;
    else adc_rd_done <= 1'b0;
  end
  // ADC SPI word index
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) adc_word_idx <= 4'd0;
    else if (next_cmd && cmd_word[31:30] == CMD_ADC_RD) adc_word_idx <= 4'd0;
    else if (state == S_ADC_RD && adc_spi_command_done && !last_adc_word) adc_word_idx <= adc_word_idx + 1;
  end

  //// SPI MOSI control
  // Start the next SPI command
  assign start_spi_command = (next_cmd && cmd_word[31:30] == CMD_ADC_RD)
                             || (adc_spi_command_done && (state != S_ADC_RD || !last_adc_word))
                             || (state == S_INIT);
  // ~(Chip Select) timer
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) n_cs_timer <= 8'd0;
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
    else if (adc_spi_command_done || state == S_IDLE) n_cs <= 1'b1; // Deassert CS when SPI command is done
  end
  // ADC word SPI bit
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) spi_bit <= 5'd0;
    else if (spi_bit > 0) spi_bit <= spi_bit - 1; // Shift out bits
    else if (cs_wait_done) begin
      if (state == S_ADC_RD) spi_bit <= 5'd15; // Start with 16 bits for ADC read
      else spi_bit <= 5'd23; // Start with 24 bits for boot-up tests
    end
  end
  // SPI MOSI bit
  assign mosi = mosi_shift_reg[23];
  // MOSI shift register
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) mosi_shift_reg <= 24'd0;
    else if (spi_bit > 0) mosi_shift_reg <= {mosi_shift_reg[22:0], 1'b0}; // Shift out bits
    else if (state == S_INIT) begin // If just exiting reset:
      // Load the shift register with the command to set On-the-Fly mode
      mosi_shift_reg <= spi_reg_write_cmd(ADDR_OTF_CFG, SET_OTF_CFG_DATA);
    end else if (state == S_TEST_WR && adc_spi_command_done) begin
      mosi_shift_reg <= spi_reg_read_cmd(ADDR_OTF_CFG); // Read back the On-the-Fly mode register
    end else if (state == S_REQ_RD && adc_spi_command_done) begin
      mosi_shift_reg <= 24'd0; // No-op during the word when reading back the On-the-Fly mode register
    end else if ((next_cmd && (next_cmd_state == S_ADC_RD))
                 || ((state == S_ADC_RD) && adc_spi_command_done)) begin
      if (adc_word_idx < 8) mosi_shift_reg <= {spi_req_otf_sample_cmd(adc_word_idx[2:0]), 8'd0};
      else if (adc_word_idx == 8) mosi_shift_reg <= {spi_req_otf_sample_cmd(3'b0), 8'd0};
    end
  end
  // Start MISO read in MOSI clock domain (should show up 1 cycle later on readback MISO clock than equivalent MOSI clock cycle)
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) start_miso_mosi_clk <= 1'b0; // Reset start MISO read signal on reset or error
    else if ((state == S_TEST_RD || (state == S_ADC_RD && adc_word_idx > 0))
             && cs_wait_done) start_miso_mosi_clk <= 1'b1;
    else start_miso_mosi_clk <= 1'b0;
  end

  //// SPI MISO
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

  // ADC data output
  // Write MISO data to the data buffer when two words are ready and buffer isn't full
  assign data_word_wr_en = try_data_write && !data_buf_full;
  // MISO data stored flag
  // Alternate storing and writing MISO data
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) miso_stored <= 1'b0; // Reset MISO stored flag on reset or error
    else if (state != S_TEST_RD && !n_miso_data_ready_mosi_clk) miso_stored <= ~miso_stored; // Toggle MISO stored flag when MISO data is ready to be read
  end
  // MISO data storage
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) miso_data_storage <= 16'd0; // Reset MISO data storage on reset or error
    else if (state != S_TEST_RD && !n_miso_data_ready_mosi_clk) begin
      if (miso_stored) miso_data_storage <= 16'd0;
      else miso_data_storage <= miso_data_mosi_clk; // Store MISO data when not stored
    end
  end
  // ADC data write attempt
  // When two data words are ready (one stored, one just read), try to write them to the data buffer
  assign try_data_write = !n_miso_data_ready_mosi_clk && miso_stored;
  assign data_word = {miso_data_mosi_clk[15:0], miso_data_storage}; // [15:0] is the first word, [31:16] is the second word

  //// Functions for command clarity
  // SPI command to write to an ADC register
  function [23:0] spi_reg_write_cmd(input [10:0] reg_addr, input [7:0] reg_data);
    spi_reg_write_cmd = {SPI_CMD_REG_WRITE, reg_addr, reg_data};
  endfunction
  // SPI command to read from an ADC register
  function [23:0] spi_reg_read_cmd(input [10:0] reg_addr);
    spi_reg_read_cmd = {SPI_CMD_REG_READ, reg_addr, 8'd0};
  endfunction
  // SPI command to request on-the-fly sample of channel `ch`
  function [15:0] spi_req_otf_sample_cmd(input [2:0] ch);
    spi_req_otf_sample_cmd = {2'b10, ch, 11'd0};
  endfunction
endmodule
