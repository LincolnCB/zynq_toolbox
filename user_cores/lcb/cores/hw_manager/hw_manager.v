`timescale 1 ns / 1 ps

module hw_manager #(
  // Delays for the various timeouts, default clock frequency is 250 MHz
  parameter integer SHUTDOWN_FORCE_DELAY = 25000000, // 100 ms, Delay after releasing "n_shutdown_force" before pulsing "n_shutdown_rst"
  parameter integer SHUTDOWN_RESET_PULSE = 25000,    // 100 us, Pulse width for "n_shutdown_rst"
  parameter integer SHUTDOWN_RESET_DELAY = 25000000, // 100 ms, Delay after pulsing "n_shutdown_rst" before starting the system
  parameter integer BUF_LOAD_WAIT  = 250000000, // Full buffer load from DMA after "dma_en" is set
  parameter integer SPI_START_WAIT = 250000000  // SPI start after "spi_en" is set
)
(
  input   wire          clk,
  input   wire          rst,

  // Inputs
  input   wire          sys_en,         // System enable (turn the system on)
  input   wire          dac_buf_loaded, // DAC buffer pre-loaded before starting the SPI subsystem
  input   wire          spi_running,    // SPI system up and running
  input   wire          ext_shutdown,   // External shutdown
  // Configuration values
  input   wire          trig_lockout_oob,     // Trigger lockout out of bounds
  input   wire          cal_offset_oob,       // Calibration offset out of bounds
  input   wire          dac_divider_oob,      // DAC divider out of bounds
  input   wire          integ_thresh_avg_oob, // Integrator threshold average out of bounds
  input   wire          integ_window_oob,     // Integrator window out of bounds
  input   wire          integ_en_oob,         // Integrator enable register out of bounds
  input   wire          sys_en_oob,           // System enable register out of bounds
  input   wire          lock_viol,      // Configuration lock violation
  // Shutdown sense
  input   wire  [ 7:0]  shutdown_sense, // Shutdown sense (per board)
  // Integrator
  input   wire  [ 7:0]  dac_over_thresh, // DAC over threshold (per board)
  input   wire  [ 7:0]  adc_over_thresh, // ADC over threshold (per board)
  input   wire  [ 7:0]  dac_thresh_underflow, // DAC threshold core FIFO underflow (per board)
  input   wire  [ 7:0]  dac_thresh_overflow,  // DAC threshold core FIFO overflow (per board)
  input   wire  [ 7:0]  adc_thresh_underflow, // ADC threshold core FIFO underflow (per board)
  input   wire  [ 7:0]  adc_thresh_overflow,  // ADC threshold core FIFO overflow (per board)
  // DAC/ADC
  input   wire  [ 7:0]  dac_buf_underflow, // DAC buffer underflow (per board)
  input   wire  [ 7:0]  dac_buf_overflow,  // DAC buffer overflow (per board)
  input   wire  [ 7:0]  adc_buf_underflow, // ADC buffer underflow (per board)
  input   wire  [ 7:0]  adc_buf_overflow,  // ADC buffer overflow (per board)
  input   wire  [ 7:0]  premat_dac_trig, // Premature DAC trigger (per board)
  input   wire  [ 7:0]  premat_adc_trig, // Premature ADC trigger (per board)
  input   wire  [ 7:0]  premat_dac_div, // Premature DAC division (per board)
  input   wire  [ 7:0]  premat_adc_div, // Premature ADC division (per board)

  // Outputs
  output  reg           sys_rst,        // System reset
  output  reg           unlock_cfg,     // Lock configuration
  output  reg           dma_en,         // DMA enable
  output  reg           spi_en,         // SPI subsystem enable
  output  reg           trig_en,        // Trigger enable
  output  reg           n_shutdown_force, // Shutdown force (negated)
  output  reg           n_shutdown_rst, // Shutdown reset (negated)
  output  wire  [31:0]  status_word,    // Status - Status word
  output  reg           ps_interrupt    // Interrupt signal
);

  // Internal signals
  reg [3:0]  state;       // State machine state
  reg [31:0] timer;       // Timer for various timeouts
  reg [2:0]  board_num;   // Status - Board number (if applicable)
  reg [24:0] status_code; // Status - Status code

  // Concatenated status word
  assign status_word = {board_num, status_code, state};

  // State encoding
  localparam  IDLE         = 4'd1,
              RELEASE_SD_F = 4'd2,
              PULSE_SD_RST = 4'd3,
              SD_RST_DELAY = 4'd4,
              START_DMA    = 4'd5,
              START_SPI    = 4'd6,
              RUNNING      = 4'd7,
              HALTED       = 4'd8;

  // Status codes
  localparam  STATUS_OK                   = 25'd1,
              STATUS_PS_SHUTDOWN          = 25'd2,
              STATUS_TRIG_LOCKOUT_OOB     = 25'd3,
              STATUS_CAL_OFFSET_OOB       = 25'd4,
              STATUS_DAC_DIVIDER_OOB      = 25'd5,
              STATUS_INTEG_THRESH_AVG_OOB = 25'd6,
              STATUS_INTEG_WINDOW_OOB     = 25'd7,
              STATUS_INTEG_EN_OOB         = 25'd8,
              STATUS_SYS_EN_OOB           = 25'd9,
              STATUS_LOCK_VIOL            = 25'd10,
              STATUS_SHUTDOWN_SENSE       = 25'd11,
              STATUS_EXT_SHUTDOWN         = 25'd12,
              STATUS_DAC_OVER_THRESH      = 25'd13,
              STATUS_ADC_OVER_THRESH      = 25'd14,
              STATUS_DAC_THRESH_UNDERFLOW = 25'd15,
              STATUS_DAC_THRESH_OVERFLOW  = 25'd16,
              STATUS_ADC_THRESH_UNDERFLOW = 25'd17,
              STATUS_ADC_THRESH_OVERFLOW  = 25'd18,
              STATUS_DAC_BUF_UNDERFLOW    = 25'd19,
              STATUS_DAC_BUF_OVERFLOW     = 25'd20,
              STATUS_ADC_BUF_UNDERFLOW    = 25'd21,
              STATUS_ADC_BUF_OVERFLOW     = 25'd22,
              STATUS_PREMAT_DAC_TRIG      = 25'd23,
              STATUS_PREMAT_ADC_TRIG      = 25'd24,
              STATUS_PREMAT_DAC_DIV       = 25'd25,
              STATUS_PREMAT_ADC_DIV       = 25'd26,
              STATUS_DAC_BUF_FILL_TIMEOUT = 25'd27,
              STATUS_SPI_START_TIMEOUT    = 25'd28;

  // Main state machine
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= IDLE;
      timer <= 0;
      sys_rst <= 1;
      n_shutdown_force <= 0;
      n_shutdown_rst <= 1;
      unlock_cfg <= 1;
      dma_en <= 0;
      spi_en <= 0;
      trig_en <= 0;
      status_code <= STATUS_OK;
      board_num <= 0;
      ps_interrupt <= 0;
    end else begin

      // State machine
      case (state)

        // Idle state, hardware shut down, waiting for system enable to go high
        // When enabled, remove the system reset and shutdown force, lock the config registers
        IDLE: begin
          if (sys_en) begin
            // Check for out of bounds configuration values
            if (trig_lockout_oob) begin // Trigger lockout out of bounds
              state <= HALTED;
              status_code <= STATUS_TRIG_LOCKOUT_OOB;
              ps_interrupt <= 1;
            end else if (cal_offset_oob) begin // Calibration offset out of bounds
              state <= HALTED;
              status_code <= STATUS_CAL_OFFSET_OOB;
              ps_interrupt <= 1;
            end else if (dac_divider_oob) begin // DAC divider out of bounds
              state <= HALTED;
              status_code <= STATUS_DAC_DIVIDER_OOB;
              ps_interrupt <= 1;
            end else if (integ_thresh_avg_oob) begin // Integrator threshold average out of bounds
              state <= HALTED;
              status_code <= STATUS_INTEG_THRESH_AVG_OOB;
              ps_interrupt <= 1;
            end else if (integ_window_oob) begin // Integrator window out of bounds
              state <= HALTED;
              status_code <= STATUS_INTEG_WINDOW_OOB;
              ps_interrupt <= 1;
            end else if (integ_en_oob) begin // Integrator enable out of bounds
              state <= HALTED;
              status_code <= STATUS_INTEG_EN_OOB;
              ps_interrupt <= 1;
            end else if (sys_en_oob) begin // System enable out of bounds
              state <= HALTED;
              status_code <= STATUS_SYS_EN_OOB;
              ps_interrupt <= 1;
            end else begin // Start bootup
              state <= RELEASE_SD_F;
              timer <= 0;
              sys_rst <= 0;
              unlock_cfg <= 0;
              n_shutdown_force <= 1;
            end
          end // if (sys_en)
          
        end // IDLE

        // Wait for a delay between releasing the shutdown force and pulsing the shutdown reset
        RELEASE_SD_F: begin
          if (timer >= SHUTDOWN_FORCE_DELAY) begin
            state <= PULSE_SD_RST;
            timer <= 0;
            n_shutdown_rst <= 0;
          end else begin
            timer <= timer + 1;
          end // if (timer >= SHUTDOWN_FORCE_DELAY)
        end // RELEASE_SD_F

        // Pulse the shutdown reset for a short time
        PULSE_SD_RST: begin
          if (timer >= SHUTDOWN_RESET_PULSE) begin
            state <= SD_RST_DELAY;
            timer <= 0;
            n_shutdown_rst <= 1;
          end else begin
            timer <= timer + 1;
          end // if (timer >= SHUTDOWN_RESET_PULSE)
        end // PULSE_SD_RST

        // Wait for a delay after pulsing the shutdown reset before starting the system
        SD_RST_DELAY: begin
          if (timer >= SHUTDOWN_RESET_DELAY) begin
            state <= START_DMA;
            timer <= 0;
            dma_en <= 1;
          end else begin
            timer <= timer + 1;
          end // if (timer >= SHUTDOWN_RESET_DELAY)
        end // SD_RST_DELAY

        // Wait for the DAC buffer to fill from the DMA before starting the SPI
        // If the buffer doesn't fill in time, halt the system
        START_DMA: begin
          if (dac_buf_loaded) begin
            state <= START_SPI;
            timer <= 0;
            spi_en <= 1;
          end else if (timer >= BUF_LOAD_WAIT) begin
            state <= HALTED;
            timer <= 0;
            sys_rst <= 1;
            n_shutdown_force <= 0;
            dma_en <= 0;
            status_code <= STATUS_DAC_BUF_FILL_TIMEOUT;
            ps_interrupt <= 1;
          end else begin
            timer <= timer + 1;
          end // if (dac_buf_loaded)
        end // START_DMA

        // Wait for the SPI subsystem to start before running the system
        // If the SPI subsystem doesn't start in time, halt the system
        START_SPI: begin
          if (spi_running) begin
            state <= RUNNING;
            timer <= 0;
            trig_en <= 1;
            ps_interrupt <= 1;
          end else if (timer >= SPI_START_WAIT) begin
            state <= HALTED;
            timer <= 0;
            sys_rst <= 1;
            n_shutdown_force <= 0;
            dma_en <= 0;
            spi_en <= 0;
            status_code <= STATUS_SPI_START_TIMEOUT;
            ps_interrupt <= 1;
          end else begin
            timer <= timer + 1;
          end // if (spi_running)
        end // START_SPI

        // Main running state, check for various error conditions or shutdowns
        RUNNING: begin
          // Reset the interrupt if needed
          if (ps_interrupt) begin
            ps_interrupt <= 0;
          end // if (ps_interrupt)

          // Error/halt state check
          if (!sys_en 
              || lock_viol
              || shutdown_sense 
              || ext_shutdown 
              || dac_over_thresh 
              || adc_over_thresh 
              || dac_thresh_underflow 
              || dac_thresh_overflow 
              || adc_thresh_underflow 
              || adc_thresh_overflow 
              || dac_buf_underflow 
              || dac_buf_overflow 
              || adc_buf_underflow 
              || adc_buf_overflow 
              || premat_dac_trig 
              || premat_adc_trig 
              || premat_dac_div 
              || premat_adc_div
              ) begin
            // Set the status code and halt the system
            state <= HALTED;
            timer <= 0;
            sys_rst <= 1;
            n_shutdown_force <= 0;
            dma_en <= 0;
            spi_en <= 0;
            trig_en <= 0;
            ps_interrupt <= 1;

            // Processing system shutdown
            if (!sys_en) status_code <= STATUS_PS_SHUTDOWN;

            // Configuration lock violation
            else if (lock_viol) begin
              status_code <= STATUS_LOCK_VIOL;
            end // if (lock_viol)

            // Hardware shutdown sense core detected a shutdown
            else if (shutdown_sense) begin
              status_code <= STATUS_SHUTDOWN_SENSE;
              board_num <= extract_board_num(shutdown_sense);
            end // if (shutdown_sense)

            // External shutdown
            else if (ext_shutdown) status_code <= STATUS_EXT_SHUTDOWN;

            // DAC over threshold
            else if (dac_over_thresh) begin
              status_code <= STATUS_DAC_OVER_THRESH;
              board_num <= extract_board_num(dac_over_thresh);
            end // if (dac_over_thresh)

            // ADC over threshold
            else if (adc_over_thresh) begin
              status_code <= STATUS_ADC_OVER_THRESH;
              board_num <= extract_board_num(adc_over_thresh);
            end // if (adc_over_thresh)

            // DAC threshold core FIFO underflow
            else if (dac_thresh_underflow) begin
              status_code <= STATUS_DAC_THRESH_UNDERFLOW;
              board_num <= extract_board_num(dac_thresh_underflow);
            end // if (dac_thresh_underflow)

            // DAC threshold core FIFO overflow
            else if (dac_thresh_overflow) begin
              status_code <= STATUS_DAC_THRESH_OVERFLOW;
              board_num <= extract_board_num(dac_thresh_overflow);
            end // if (dac_thresh_overflow)

            // ADC threshold core FIFO underflow
            else if (adc_thresh_underflow) begin
              status_code <= STATUS_ADC_THRESH_UNDERFLOW;
              board_num <= extract_board_num(adc_thresh_underflow);
            end // if (adc_thresh_underflow)

            // ADC threshold core FIFO overflow
            else if (adc_thresh_overflow) begin
              status_code <= STATUS_ADC_THRESH_OVERFLOW;
              board_num <= extract_board_num(adc_thresh_overflow);
            end // if (adc_thresh_overflow)

            // DAC buffer underflow
            else if (dac_buf_underflow) begin
              status_code <= STATUS_DAC_BUF_UNDERFLOW;
              board_num <= extract_board_num(dac_buf_underflow);
            end // if (dac_buf_underflow)

            // DAC buffer overflow
            else if (dac_buf_overflow) begin
              status_code <= STATUS_DAC_BUF_OVERFLOW;
              board_num <= extract_board_num(dac_buf_overflow);
            end // if (dac_buf_overflow)

            // ADC buffer underflow
            else if (adc_buf_underflow) begin
              status_code <= STATUS_ADC_BUF_UNDERFLOW;
              board_num <= extract_board_num(adc_buf_underflow);
            end // if (adc_buf_underflow)

            // ADC buffer overflow
            else if (adc_buf_overflow) begin
              status_code <= STATUS_ADC_BUF_OVERFLOW;
              board_num <= extract_board_num(adc_buf_overflow);
            end // if (adc_buf_overflow)

            // Premature DAC trigger
            else if (premat_dac_trig) begin
              status_code <= STATUS_PREMAT_DAC_TRIG;
              board_num <= extract_board_num(premat_dac_trig);
            end // if (premat_dac_trig)

            // Premature ADC trigger
            else if (premat_adc_trig) begin
              status_code <= STATUS_PREMAT_ADC_TRIG;
              board_num <= extract_board_num(premat_adc_trig);
            end // if (premat_adc_trig)

            // Premature DAC divider (DAC transfer took longer than the DAC divider)
            else if (premat_dac_div) begin
              status_code <= STATUS_PREMAT_DAC_DIV;
              board_num <= extract_board_num(premat_dac_div);
            end // if (premat_dac_div)

            // Premature ADC division (ADC transfer took longer than the ADC divider)
            else if (premat_adc_div) begin
              status_code <= STATUS_PREMAT_ADC_DIV;
              board_num <= extract_board_num(premat_adc_div);
            end // if (premat_adc_div)

          end // Error/halt state check
        end // RUNNING

        // Wait in the halted state until the system enable goes low
        HALTED: begin
          // Reset the interrupt if needed
          if (ps_interrupt) begin
            ps_interrupt <= 0;
          end // if (ps_interrupt)
          // If the system enable goes low, go to IDLE and clear the status code
          if (~sys_en) begin 
            state <= IDLE;
            status_code <= STATUS_OK;
            board_num <= 0;
            unlock_cfg <= 1;
          end
        end // HALTED

      endcase // case (state)
    end // if (rst) else
  end // always @(posedge clk or posedge rst)

  // Function to extract the board number from an 8-bit signal
  function [2:0] extract_board_num;
    input [7:0] signal;
    begin
      case (1'b1)
        signal[0]: extract_board_num = 3'd0;
        signal[1]: extract_board_num = 3'd1;
        signal[2]: extract_board_num = 3'd2;
        signal[3]: extract_board_num = 3'd3;
        signal[4]: extract_board_num = 3'd4;
        signal[5]: extract_board_num = 3'd5;
        signal[6]: extract_board_num = 3'd6;
        signal[7]: extract_board_num = 3'd7;
        default: extract_board_num = 3'd0;
      endcase
    end
  endfunction

endmodule
