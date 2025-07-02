module shim_ads816x_adc_ctrl (
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
  input  wire        miso
);

  // Internal constants
  localparam ADC_WORD_MIN_TIME = 6'd41;
  localparam ADC_SPI_START_DELAY = 6'd7;
  localparam ADC_SPI_START_TIME = ADC_WORD_MIN_TIME - ADC_SPI_START_DELAY;

  // ADC SPI commands
  localparam SPI_CMD_REG_WRITE = 5'b00001;
  localparam SPI_CMD_REG_READ  = 5'b00010;

  // States
  localparam S_INIT      = 3'd0;
  localparam S_IDLE      = 3'd1;
  localparam S_DELAY     = 3'd2;
  localparam S_TRIG_WAIT = 3'd3;
  localparam S_ADC_RD    = 3'd4;
  localparam S_ERROR     = 3'd5;

  // Command types
  localparam CMD_NO_OP   = 2'b00;
  localparam CMD_ADC_RD  = 2'b01;
  localparam CMD_SET_ORD = 2'b10;
  localparam CMD_CANCEL  = 2'b11;

  localparam TRIG_BIT = 29;
  localparam CONT_BIT = 28;

  // State and command processing
  reg  [ 2:0] state;
  wire        cmd_done;
  wire        next_cmd;
  wire [ 2:0] next_cmd_state;
  wire        cancel_wait;
  // Command word toggled bits
  reg         wait_for_trig;
  reg         expect_next;
  // Delay timer
  reg  [24:0] delay_timer;
  // Sample order for ADC
  reg  [ 2:0] sample_order [0:7];
  // ADC control signals
  wire        write_next_spi_word;
  reg         adc_rd_done;
  reg  [ 5:0] adc_update_timer;
  reg  [ 3:0] adc_word_idx;
  wire        last_adc_word;
  reg  [ 4:0] spi_bit;
  reg  [23:0] adc_shift_reg;
  reg  [ 2:0] adc_load_stage;

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
                           : (cmd_word[31:30] == CMD_ADC_RD) ? S_ADC_RD // If command is DAC write, go to DAC_WR state
                           : (cmd_word[31:30] == CMD_SET_ORD) ? S_IDLE // If command is SET_ORD, go to IDLE
                           : (cmd_word[31:30] == CMD_CANCEL) ? S_IDLE // If command is CANCEL, go to IDLE
                           : S_ERROR; // If command is unrecognized, go to ERROR state
  // Signal indicating the core is waiting for a trigger
  assign waiting_for_trig = (state == S_TRIG_WAIT);
  // State transition logic
  always @(posedge clk) begin
    if (!resetn)                                  state <= S_INIT;
    else if (state == S_INIT)                     state <= S_IDLE;
    else if (trigger && !waiting_for_trig)        state <= S_ERROR;
    else if (cmd_buf_underflow)                   state <= S_ERROR;
    else if (data_buf_overflow)                   state <= S_ERROR;
    else if (cancel_wait)                         state <= S_IDLE;
    else if (cmd_done)                            state <= next_cmd_state;
    else if (state == S_ADC_RD && adc_rd_done)    state <= wait_for_trig ? S_TRIG_WAIT : S_DELAY;
    else state <= state;
  end
  // Setup done logic
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) setup_done <= 1'b0;
    else if (state == S_INIT) setup_done <= 1'b1;
  end

  //// Command bits processing
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) begin
      wait_for_trig <= 1'b0;
      expect_next <= 1'b0;
    end else if (next_cmd && ((cmd_word[31:30] == CMD_NO_OP) || (cmd_word[31:30] == CMD_ADC_RD))) begin
      wait_for_trig <= cmd_word[TRIG_BIT];
      expect_next <= cmd_word[CONT_BIT];
    end
  end
  // Command word read enable
  assign cmd_word_rd_en = (state != S_ERROR) && !cmd_buf_empty
                          && (cmd_done || cancel_wait);

  // Delay timer logic
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) delay_timer <= 25'd0;
    else if (next_cmd
             && ((cmd_word[31:30] == CMD_ADC_RD) || (cmd_word[31:30] == CMD_NO_OP))
             && !cmd_word[TRIG_BIT]) delay_timer <= cmd_word[24:0];
    else if (delay_timer > 0) delay_timer <= delay_timer - 1;
  end

  //// Errors
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
    else if (state == S_ADC_RD && data_buf_full) data_buf_overflow <= 1'b1;
  end

  // Sample order logic
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

  //// ADC boot-up SPI sequence
  // TODO: Implement boot-up sequence
  always @(posedge clk) begin
    if (!resetn) boot_fail <= 1'b0;
  end


  //// ADC word sequencing
  // ADC word count status
  assign last_adc_word = (adc_word_idx == 8);
  // ADC word timer logic
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) adc_update_timer <= 6'd0;
    else if (next_cmd && cmd_word[31:30] == CMD_ADC_RD) adc_update_timer <= ADC_WORD_MIN_TIME;
    else if (state == S_ADC_RD && adc_update_timer == 0 && !last_adc_word) adc_update_timer <= ADC_WORD_MIN_TIME;
    else if (state == S_ADC_RD && adc_update_timer > 0) adc_update_timer <= adc_update_timer - 1;
  end
  // ADC done signal
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) adc_rd_done <= 1'b0;
    else if (state == S_ADC_RD && adc_update_timer == 0 && last_adc_word) adc_rd_done <= 1'b1;
    else adc_rd_done <= 1'b0;
  end
  // ADC SPI word index
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) adc_word_idx <= 4'd0;
    else if (next_cmd && cmd_word[31:30] == CMD_ADC_RD) adc_word_idx <= 4'd0;
    else if (state == S_ADC_RD && adc_update_timer == 0 && !last_adc_word) adc_word_idx <= adc_word_idx + 1;
  end

  //// SPI MOSI control
  // Write next SPI word signal
  assign write_next_spi_word = 0; // TODO: Implement logic to trigger writing the next SPI word
  // ADC word SPI bit
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) spi_bit <= 5'd0;
    else if (spi_bit > 0) spi_bit <= spi_bit - 1; // Shift out bits
    else if (write_next_spi_word) begin
      if (state == S_ADC_RD) spi_bit <= 5'd15; // Start with 16 bits for ADC read
      else if (state == S_INIT) spi_bit <= 5'd23; // Start with 24 bits for boot-up sequence
    end
  end
  // n_CS signal
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) n_cs <= 1'b1;
    else if (write_next_spi_word) n_cs <= 1'b0; // Assert CS when starting a new SPI word
    else if (spi_bit == 0) n_cs <= 1'b1; // Deassert CS when done
  end
  // SPI MOSI bit
  assign mosi = adc_shift_reg[23];
  // MOSI shift register
  always @(posedge clk) begin
    if (!resetn || state == S_ERROR) adc_shift_reg <= 24'd0;
    else if (spi_bit > 0) adc_shift_reg <= {adc_shift_reg[22:0], 1'b0}; // Shift out bits
    else if (write_next_spi_word) begin
      if (state == S_ADC_RD) begin
        if (adc_word_idx < 8) adc_shift_reg <= {2'b10, sample_order[adc_word_idx[2:0]], 11'd0, 8'd0};
        else if (adc_word_idx == 8) adc_shift_reg <= {5'b10000, 19'd0};
      end else if (state == S_INIT) begin
        adc_shift_reg <= 24'd0; // TODO: Implement boot-up sequence
      end
    end
  end

  //// SPI MISO
  // TODO: Handle MISO readback

endmodule
