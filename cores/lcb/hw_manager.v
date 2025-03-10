`timescale 1 ns / 1 ps

module hw_manager #(
  // Delays for the various timeouts, default to 1 second at 250 MHz
  parameter integer BUF_LOAD_WAIT  = 250000000, // Full buffer load from DMA after "dma_en" is set
  parameter integer SPI_START_WAIT = 250000000, // SPI start after "spi_en" is set
  parameter integer SPI_STOP_WAIT  = 250000000  // SPI stop after "spi_en" is cleared
)
(
  input   wire          clk,
  input   wire          rst,

  // Inputs
  input   wire          sys_en,         // System enable
  input   wire          dac_buf_full,   // DAC buffer full
  input   wire          spi_running,    // SPI running
  input   wire          over_thresh,    // Over threshold
  input   wire          shutdown_sense, // Shutdown sense
  input   wire  [ 2:0]  sense_num,      // Shutdown sense number
  input   wire          ext_shutdown,   // External shutdown
  input   wire  [ 7:0]  dac_empty_read, // DAC empty read (per board)
  input   wire  [ 7:0]  adc_full_write, // ADC full write (per board)
  input   wire  [ 7:0]  premat_trig,    // Premature trigger (per board)
  input   wire  [ 7:0]  premat_dac_div, // Premature DAC division (per board)
  input   wire  [ 7:0]  premat_adc_div, // Premature ADC division (per board)

  // Outputs
  output  reg           sys_rst,        // System reset
  output  reg           dma_en,         // DMA enable
  output  reg           spi_en,         // SPI subsystem enable
  output  reg           n_sck_pow,      // SPI clock power (negated)
  output  reg           shutdown_force, // Shutdown force
  output  reg           n_shutdown_rst, // Shutdown reset (negated)
  output  reg   [31:0]  status_word     // Status - Status word
);

  // Internal signals
  reg [2:0]  state;       // State machine state
  reg [31:0] timer;       // Timer for various timeouts
  reg        prev_sys_en; // Previous system enable (for rising edge detection)
  reg        running;     // Status - Running
  reg        stopping;    // Status - Stopping
  reg        dma_running; // Status - DMA running
  reg        halted;      // Status - Halted
  reg [2:0]  board_num;   // Status - Board number (if applicable)
  reg [23:0] status_code; // Status - Status code

  // Concatenated status word
  assign status_word = {running, stopping, dma_running, spi_running, halted, board_num, status_code};

  // State encoding
  localparam  IDLE      = 3'd0,
              STARTING  = 3'd1,
              START_DMA = 3'd2,
              START_SPI = 3'd3,
              RUNNING   = 3'd4,
              STOPPING  = 3'd5,
              HALTED    = 3'd6;

  // Status codes
  localparam  STATUS_OK                   = 24'h0,
              STATUS_PS_SHUTDOWN          = 24'h1,
              STATUS_DAC_BUF_FILL_TIMEOUT = 24'h2,
              STATUS_SPI_START_TIMEOUT    = 24'h3,
              STATUS_OVER_THRESH          = 24'h4,
              STATUS_SHUTDOWN_SENSE       = 24'h5,
              STATUS_EXT_SHUTDOWN         = 24'h6,
              STATUS_DAC_EMPTY_READ       = 24'h7,
              STATUS_ADC_FULL_WRITE       = 24'h8,
              STATUS_PREMAT_TRIG          = 24'h9,
              STATUS_PREMAT_DAC_DIV       = 24'hA,
              STATUS_PREMAT_ADC_DIV       = 24'hB;

  // Main state machine
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= IDLE;
      sys_rst <= 1;
      prev_sys_en <= 1;
      dma_en <= 0;
      spi_en <= 0;
      n_sclk_pow <= 1;
      shutdown_force <= 1;
      n_shutdown_rst <= 1;
      halted <= 0;
      status_code <= STATUS_OK;
      board_num <= 0;
      timer <= 0;
      stopping <= 0;
      running <= 0;
    end else begin

      // State machine
      case (state)

        // Idle state, hardware shut down, waiting for system enable to go high from low
        // When enabled, remove the system reset and shutdown force, reset the shutdown
        IDLE: begin
          if (sys_en & ~prev_sys_en) begin
            state <= STARTING;
            prev_sys_en <= 1;
            running <= 1;
            sys_rst <= 0;
            shutdown_force <= 0;
            n_shutdown_rst <= 0;
          end else begin
            prev_sys_en <= sys_en;
          end // if (sys_en & ~prev_sys_en)
        end // IDLE

        // Turn off the shutdown reset, begin loading the DMA buffer
        STARTING: begin
          state <= START_DMA;
          n_shutdown_rst <= 1;
          dma_en <= 1;
          timer <= 0;
        end

        // Wait for the DAC buffer to fill from the DMA before starting the SPI
        // If the buffer doesn't fill in time, halt the system
        START_DMA: begin
          if (dac_buf_full) begin
            state <= START_SPI;
            timer <= 0;
            dma_running <= 1;
            spi_en <= 1;
            n_sclk_pow <= 0;
          end else if (timer > BUF_LOAD_WAIT) begin
            state <= HALTED;
            timer <= 0;
            halted <= 1;
            status_code <= STATUS_DAC_BUF_FILL_TIMEOUT;
            running <= 0;
            dma_en <= 0;
            sys_rst <= 1;
            shutdown_force <= 1;
          end else begin
            timer <= timer + 1;
          end // if (dac_buf_full)
        end // START_DMA

        // Wait for the SPI subsystem to start before running the system
        // If the SPI subsystem doesn't start in time, halt the system
        START_SPI: begin
          if (spi_running) begin
            state <= RUNNING;
            timer <= 0;
          end else if (timer > SPI_START_WAIT) begin
            state <= HALTED;
            timer <= 0;
            halted <= 1;
            status_code <= STATUS_SPI_START_TIMEOUT;
            running <= 0;
            dma_en <= 0;
            dma_running <= 0;
            spi_en <= 0;
            n_sclk_pow <= 1;
            sys_rst <= 1;
            shutdown_force <= 1;
          end else begin
            timer <= timer + 1;
          end // if (spi_running)
        end // START_SPI

        // Main running state, check for various error conditions or shutdowns
        RUNNING: begin
          if (!sys_en || over_thresh || shutdown_sense || ext_shutdown || dac_empty_read || adc_full_write || premat_trig || premat_dac_div || premat_adc_div) begin
            // Set the status code and begin the shutdown process
            state <= STOPPING;
            timer <= 0;
            stopping <= 1;
            spi_en <= 0;

            // Processing system shutdown
            if (!sys_en) status_code <= STATUS_PS_SHUTDOWN;

            // Integrator core over threshold
            else if (over_thresh) status_code <= STATUS_OVER_THRESH;

            // Hardware shutdown sense core detected a shutdown
            else if (shutdown_sense) begin
              status_code <= STATUS_SHUTDOWN_SENSE;
              board_num <= sense_num;
            end // if (shutdown_sense)

            // External shutdown
            else if (ext_shutdown) status_code <= STATUS_EXT_SHUTDOWN;

            // DAC read attempt from empty buffer
            else if (dac_empty_read) begin
              status_code <= STATUS_DAC_EMPTY_READ;
              board_num <=  dac_empty_read[0] ? 3'd0 :
                    dac_empty_read[1] ? 3'd1 :
                    dac_empty_read[2] ? 3'd2 :
                    dac_empty_read[3] ? 3'd3 :
                    dac_empty_read[4] ? 3'd4 :
                    dac_empty_read[5] ? 3'd5 :
                    dac_empty_read[6] ? 3'd6 : 3'd7;
            end // if (dac_empty_read)

            // ADC write attempt to full buffer
            else if (adc_full_write) begin
              status_code <= STATUS_ADC_FULL_WRITE;
              board_num <=  adc_full_write[0] ? 3'd0 :
                    adc_full_write[1] ? 3'd1 :
                    adc_full_write[2] ? 3'd2 :
                    adc_full_write[3] ? 3'd3 :
                    adc_full_write[4] ? 3'd4 :
                    adc_full_write[5] ? 3'd5 :
                    adc_full_write[6] ? 3'd6 : 3'd7;
            end // if (adc_full_write)

            // Premature trigger (trigger occurred before the DAC was pre-loaded and ready)
            else if (premat_trig) begin
              status_code <= STATUS_PREMAT_TRIG;
              board_num <=  premat_trig[0] ? 3'd0 :
                    premat_trig[1] ? 3'd1 :
                    premat_trig[2] ? 3'd2 :
                    premat_trig[3] ? 3'd3 :
                    premat_trig[4] ? 3'd4 :
                    premat_trig[5] ? 3'd5 :
                    premat_trig[6] ? 3'd6 : 3'd7;
            end // if (premat_trig)

            // Premature DAC divider (DAC transfer took longer than the DAC divider)
            else if (premat_dac_div) begin
              status_code <= STATUS_PREMAT_DAC_DIV;
              board_num <=  premat_dac_div[0] ? 3'd0 :
                    premat_dac_div[1] ? 3'd1 :
                    premat_dac_div[2] ? 3'd2 :
                    premat_dac_div[3] ? 3'd3 :
                    premat_dac_div[4] ? 3'd4 :
                    premat_dac_div[5] ? 3'd5 :
                    premat_dac_div[6] ? 3'd6 : 3'd7;
            end // if (premat_dac_div)

            // Premature ADC division (ADC transfer took longer than the ADC divider)
            else if (premat_adc_div) begin
              status_code <= STATUS_PREMAT_ADC_DIV;
              board_num <=  premat_adc_div[0] ? 3'd0 :
                    premat_adc_div[1] ? 3'd1 :
                    premat_adc_div[2] ? 3'd2 :
                    premat_adc_div[3] ? 3'd3 :
                    premat_adc_div[4] ? 3'd4 :
                    premat_adc_div[5] ? 3'd5 :
                    premat_adc_div[6] ? 3'd6 : 3'd7;
            end // if (premat_adc_div)

          end // if (!sys_en || over_thresh || shutdown_sense || ext_shutdown || dac_empty_read || adc_full_write || premat_trig || premat_dac_div || premat_adc_div)
        end // RUNNING

        // Stop the system and wait for the SPI subsystem to stop
        STOPPING: begin
          if (!spi_running) begin
            state <= IDLE;
            timer <= 0;
            running <= 0;
            sys_rst <= 1;
            dma_en <= 0;
            dma_running <= 0;
            n_sclk_pow <= 1;
            shutdown_force <= 1;
          end else if (timer > SPI_STOP_WAIT) begin
            state <= HALTED;
            timer <= 0;
            halted <= 1;
            running <= 0;
            dma_en <= 0;
            dma_running <= 0;
            n_sclk_pow <= 1;
            sys_rst <= 1;
            shutdown_force <= 1;
          end else begin
            timer <= timer + 1;
          end
        end // STOPPING

        // Wait in the halted state until the system enable goes low
        HALTED: begin
          if (~sys_en) begin 
            state <= IDLE;
            halted <= 0;
            status_code <= STATUS_OK;
            prev_sys_en <= 0;
          end
        end // HALTED

      endcase // case (state)
    end // if (rst) else
  end // always @(posedge clk or posedge rst)

endmodule
