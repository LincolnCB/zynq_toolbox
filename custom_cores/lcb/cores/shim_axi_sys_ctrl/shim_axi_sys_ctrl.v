`timescale 1 ns / 1 ps

module shim_axi_sys_ctrl #
(
  parameter integer AXI_ADDR_WIDTH = 16,
  parameter integer INTEG_THRESHOLD_AVERAGE_DEFAULT = 16384,
  parameter integer INTEG_WINDOW_DEFAULT = 5000000, // 100 ms at 50MHz
  parameter integer INTEG_EN_DEFAULT = 1,
  parameter integer BOOT_TEST_SKIP_DEFAULT = 0, // Default to not skipping boot test for all 16 cores
  parameter integer DEBUG = 0, // Default to no debug
  parameter integer MOSI_SCK_POL_DEFAULT = 0, // Default to 0 MOSI SCK polarity (don't invert)
  parameter integer MISO_SCK_POL_DEFAULT = 1 // Default to 1 MISO SCK polarity (invert)
)
(
  // System signals
  input  wire                       aclk,
  input  wire                       aresetn,

  input  wire                       unlock,

  // Configuration outputs
  output wire                sys_en,
  output reg  [16:0]         cmd_buf_reset,
  output reg  [16:0]         data_buf_reset,
  output reg  [14:0]         integ_thresh_avg,
  output reg  [31:0]         integ_window,
  output reg                 integ_en,
  output reg  [15:0]         boot_test_skip,
  output reg  [15:0]         debug,
  output reg                 mosi_sck_pol,
  output reg                 miso_sck_pol,

  // Configuration bounds
  output wire  sys_en_oob,
  output wire  cmd_buf_reset_oob,
  output wire  data_buf_reset_oob,
  output wire  integ_thresh_avg_oob,
  output wire  integ_window_oob,
  output wire  integ_en_oob,
  output wire  boot_test_skip_oob,
  output wire  debug_oob,
  output wire  mosi_sck_pol_oob,
  output wire  miso_sck_pol_oob,
  output reg   lock_viol,

  // AXI4-Line subordinate port
  input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_awaddr,  // AXI4-Lite subordinate: Write address
  input  wire                       s_axi_awvalid, // AXI4-Lite subordinate: Write address valid
  output wire                       s_axi_awready, // AXI4-Lite subordinate: Write address ready
  input  wire [31:0]                s_axi_wdata,   // AXI4-Lite subordinate: Write data
  input  wire [3:0]                 s_axi_wstrb,   // AXI4-Lite subordinate: Write strobe
  input  wire                       s_axi_wvalid,  // AXI4-Lite subordinate: Write data valid
  output wire                       s_axi_wready,  // AXI4-Lite subordinate: Write data ready
  output reg  [1:0]                 s_axi_bresp,   // AXI4-Lite subordinate: Write response
  output wire                       s_axi_bvalid,  // AXI4-Lite subordinate: Write response valid
  input  wire                       s_axi_bready,  // AXI4-Lite subordinate: Write response ready
  input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_araddr,  // AXI4-Lite subordinate: Read address
  input  wire                       s_axi_arvalid, // AXI4-Lite subordinate: Read address valid
  output wire                       s_axi_arready, // AXI4-Lite subordinate: Read address ready
  output wire [31:0]                s_axi_rdata,   // AXI4-Lite subordinate: Read data
  output wire [1:0]                 s_axi_rresp,   // AXI4-Lite subordinate: Read data response
  output wire                       s_axi_rvalid,  // AXI4-Lite subordinate: Read data valid
  input  wire                       s_axi_rready   // AXI4-Lite subordinate: Read data ready
);

  function integer clogb2 (input integer value);
    for(clogb2 = 0; value > 0; clogb2 = clogb2 + 1) value = value >> 1;
  endfunction

  // Localparams for bit offsets
  localparam integer SYS_EN_32_OFFSET                  = 0;
  localparam integer CMD_BUF_RESET_32_OFFSET           = 1;
  localparam integer DATA_BUF_RESET_32_OFFSET          = 2;
  localparam integer INTEG_THRESHOLD_AVERAGE_32_OFFSET = 3;
  localparam integer INTEG_WINDOW_32_OFFSET            = 4;
  localparam integer INTEG_EN_32_OFFSET                = 5;
  localparam integer BOOT_TEST_SKIP_32_OFFSET          = 6;
  localparam integer DEBUG_32_OFFSET                   = 7;
  localparam integer MOSI_SCK_POL_32_OFFSET            = 8;
  localparam integer MISO_SCK_POL_32_OFFSET            = 9;

  // Localparams for widths
  localparam integer SYS_EN_WIDTH = 1;
  localparam integer CMD_BUF_RESET_WIDTH = 17;
  localparam integer DATA_BUF_RESET_WIDTH = 17;
  localparam integer INTEG_THRESHOLD_AVERAGE_WIDTH = 15;
  localparam integer INTEG_WINDOW_WIDTH = 32;
  localparam integer INTEG_EN_WIDTH = 1;
  localparam integer BOOT_TEST_SKIP_WIDTH = 16;
  localparam integer DEBUG_WIDTH = 16;
  localparam integer MOSI_SCK_POL_WIDTH = 1;
  localparam integer MISO_SCK_POL_WIDTH = 1;

  // Localparams for MIN/MAX values
  localparam integer SYS_EN_MAX                  = {{SYS_EN_WIDTH{1'b1}}};
  localparam integer CMD_BUF_RESET_MAX           = {{CMD_BUF_RESET_WIDTH{1'b1}}};
  localparam integer DATA_BUF_RESET_MAX          = {{DATA_BUF_RESET_WIDTH{1'b1}}};
  localparam integer INTEG_THRESHOLD_AVERAGE_MIN = {{(INTEG_THRESHOLD_AVERAGE_WIDTH-1){1'b0}}, 1'b1}; // Minimum is 1
  localparam integer INTEG_THRESHOLD_AVERAGE_MAX = {{INTEG_THRESHOLD_AVERAGE_WIDTH{1'b1}}};
  localparam integer INTEG_WINDOW_MIN            = 2048;
  localparam integer INTEG_WINDOW_MAX            = {{INTEG_WINDOW_WIDTH{1'b1}}};
  localparam integer INTEG_EN_MAX                = {{INTEG_EN_WIDTH{1'b1}}};
  localparam integer BOOT_TEST_SKIP_MAX          = {{BOOT_TEST_SKIP_WIDTH{1'b1}}};
  localparam integer DEBUG_MAX                   = {{DEBUG_WIDTH{1'b1}}};
  localparam integer MOSI_SCK_POL_MAX            = {{MOSI_SCK_POL_WIDTH{1'b1}}};
  localparam integer MISO_SCK_POL_MAX            = {{MISO_SCK_POL_WIDTH{1'b1}}};

  // Local capped default values
  localparam integer INTEG_THRESHOLD_AVERAGE_DEFAULT_CAPPED = 
    (INTEG_THRESHOLD_AVERAGE_DEFAULT < INTEG_THRESHOLD_AVERAGE_MIN) ? INTEG_THRESHOLD_AVERAGE_MIN :
    (INTEG_THRESHOLD_AVERAGE_DEFAULT > INTEG_THRESHOLD_AVERAGE_MAX) ? INTEG_THRESHOLD_AVERAGE_MAX :
    INTEG_THRESHOLD_AVERAGE_DEFAULT;
  localparam integer INTEG_WINDOW_DEFAULT_CAPPED = 
    (INTEG_WINDOW_DEFAULT < INTEG_WINDOW_MIN) ? INTEG_WINDOW_MIN :
    (INTEG_WINDOW_DEFAULT > INTEG_WINDOW_MAX) ? INTEG_WINDOW_MAX :
    INTEG_WINDOW_DEFAULT;
  localparam integer INTEG_EN_DEFAULT_CAPPED = 
    (INTEG_EN_DEFAULT > INTEG_EN_MAX) ? INTEG_EN_MAX :
    INTEG_EN_DEFAULT;
  localparam integer BOOT_TEST_SKIP_DEFAULT_CAPPED =
    (BOOT_TEST_SKIP_DEFAULT > BOOT_TEST_SKIP_MAX) ? BOOT_TEST_SKIP_MAX :
    BOOT_TEST_SKIP_DEFAULT;
  localparam integer DEBUG_DEFAULT_CAPPED =
    (DEBUG > DEBUG_MAX) ? DEBUG_MAX :
    DEBUG;
  localparam integer MOSI_SCK_POL_DEFAULT_CAPPED =
    (MOSI_SCK_POL_DEFAULT > MOSI_SCK_POL_MAX) ? MOSI_SCK_POL_MAX :
    MOSI_SCK_POL_DEFAULT;
  localparam integer MISO_SCK_POL_DEFAULT_CAPPED =
    (MISO_SCK_POL_DEFAULT > MISO_SCK_POL_MAX) ? MISO_SCK_POL_MAX :
    MISO_SCK_POL_DEFAULT;

  // Local parameters for AXI configuration
  localparam integer CFG_DATA_WIDTH = 1024;
  localparam integer AXI_DATA_WIDTH = 32;
  localparam integer ADDR_LSB = clogb2(AXI_DATA_WIDTH/8 - 1);
  localparam integer CFG_SIZE = CFG_DATA_WIDTH/AXI_DATA_WIDTH;
  localparam integer CFG_WIDTH = CFG_SIZE > 1 ? clogb2(CFG_SIZE-1) : 1;

  reg int_bvalid_reg, int_bvalid_next;
  reg int_rvalid_reg, int_rvalid_next;
  reg [AXI_DATA_WIDTH-1:0] int_rdata_reg, int_rdata_next;

  wire [AXI_DATA_WIDTH-1:0] int_data_mux [CFG_SIZE-1:0];
  wire [CFG_DATA_WIDTH-1:0] int_data_wire;
  wire [CFG_DATA_WIDTH-1:0] int_axi_data_wire;
  wire [CFG_DATA_WIDTH-1:0] int_data_modified_wire;
  wire [CFG_DATA_WIDTH-1:0] int_initial_data_wire;
  wire [CFG_SIZE-1:0] int_ce_wire;
  wire int_wvalid_wire;
  wire [1:0] int_bresp_wire;

  wire int_lock_viol_wire;
  reg  locked;

  genvar j, k;

  assign int_wvalid_wire = s_axi_awvalid & s_axi_wvalid;
  
  generate
    for(j = 0; j < CFG_SIZE; j = j + 1)
    begin : WORDS
      assign int_data_mux[j] = int_data_wire[j*AXI_DATA_WIDTH+AXI_DATA_WIDTH-1:j*AXI_DATA_WIDTH];
      assign int_ce_wire[j] = int_wvalid_wire & (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == j);
      for(k = 0; k < AXI_DATA_WIDTH; k = k + 1)
      begin : BITS
        
        // Flipflops for AXI data
        FDRE #(
          .INIT(1'b0)
        ) FDRE_data (
          .CE(int_ce_wire[j] & s_axi_wstrb[k/8]),
          .C(aclk),
          .R(~aresetn),
          .D(s_axi_wdata[k]),
          .Q(int_axi_data_wire[j*AXI_DATA_WIDTH + k])
        );

        // Track if the data has been modified since reset
        FDRE #(
          .INIT(1'b0)
        ) FDRE_data_modified (
          .CE(int_ce_wire[j] & s_axi_wstrb[k/8]),
          .C(aclk),
          .R(~aresetn),
          .D(1'b1),
          .Q(int_data_modified_wire[j*AXI_DATA_WIDTH + k])
        );
      end
    end
  endgenerate

  // Initial values (shifted)
  assign int_data_wire = int_axi_data_wire | (~int_data_modified_wire & int_initial_data_wire);
  assign int_initial_data_wire[SYS_EN_32_OFFSET*32+SYS_EN_WIDTH-1:SYS_EN_32_OFFSET*32] = {SYS_EN_WIDTH{1'b0}}; // System enable defaults to 0
  assign int_initial_data_wire[CMD_BUF_RESET_32_OFFSET*32+CMD_BUF_RESET_WIDTH-1-:CMD_BUF_RESET_WIDTH] = {CMD_BUF_RESET_WIDTH{1'b0}}; // Command buffer reset defaults to 0
  assign int_initial_data_wire[DATA_BUF_RESET_32_OFFSET*32+DATA_BUF_RESET_WIDTH-1-:DATA_BUF_RESET_WIDTH] = {DATA_BUF_RESET_WIDTH{1'b0}}; // Data buffer reset defaults to 0
  assign int_initial_data_wire[INTEG_THRESHOLD_AVERAGE_32_OFFSET*32+INTEG_THRESHOLD_AVERAGE_WIDTH-1-:INTEG_THRESHOLD_AVERAGE_WIDTH] = INTEG_THRESHOLD_AVERAGE_DEFAULT_CAPPED[INTEG_THRESHOLD_AVERAGE_WIDTH-1:0];
  assign int_initial_data_wire[INTEG_WINDOW_32_OFFSET*32+INTEG_WINDOW_WIDTH-1-:INTEG_WINDOW_WIDTH] = INTEG_WINDOW_DEFAULT_CAPPED[INTEG_WINDOW_WIDTH-1:0];
  assign int_initial_data_wire[INTEG_EN_32_OFFSET*32+INTEG_EN_WIDTH-1:INTEG_EN_32_OFFSET*32] = INTEG_EN_DEFAULT_CAPPED[INTEG_EN_WIDTH-1:0];
  assign int_initial_data_wire[BOOT_TEST_SKIP_32_OFFSET*32+BOOT_TEST_SKIP_WIDTH-1-:BOOT_TEST_SKIP_WIDTH] = BOOT_TEST_SKIP_DEFAULT_CAPPED[BOOT_TEST_SKIP_WIDTH-1:0];
  assign int_initial_data_wire[DEBUG_32_OFFSET*32+DEBUG_WIDTH-1-:DEBUG_WIDTH] = DEBUG_DEFAULT_CAPPED[DEBUG_WIDTH-1:0];
  assign int_initial_data_wire[MOSI_SCK_POL_32_OFFSET*32+MOSI_SCK_POL_WIDTH-1:MOSI_SCK_POL_32_OFFSET*32] = MOSI_SCK_POL_DEFAULT_CAPPED[MOSI_SCK_POL_WIDTH-1:0];
  assign int_initial_data_wire[MISO_SCK_POL_32_OFFSET*32+MISO_SCK_POL_WIDTH-1:MISO_SCK_POL_32_OFFSET*32] = MISO_SCK_POL_DEFAULT_CAPPED[MISO_SCK_POL_WIDTH-1:0];

  // Out of bounds checks. Use the whole word for the check to error on truncation
  assign sys_en_oob = $unsigned(int_data_wire[SYS_EN_32_OFFSET*32+SYS_EN_WIDTH-1:SYS_EN_32_OFFSET*32]) > SYS_EN_MAX;
  assign cmd_buf_reset_oob = $unsigned(int_data_wire[CMD_BUF_RESET_32_OFFSET*32+CMD_BUF_RESET_WIDTH-1:CMD_BUF_RESET_32_OFFSET*32]) > CMD_BUF_RESET_MAX;
  assign data_buf_reset_oob = $unsigned(int_data_wire[DATA_BUF_RESET_32_OFFSET*32+DATA_BUF_RESET_WIDTH-1:DATA_BUF_RESET_32_OFFSET*32]) > DATA_BUF_RESET_MAX;
  assign integ_thresh_avg_oob = $unsigned(int_data_wire[INTEG_THRESHOLD_AVERAGE_32_OFFSET*32+INTEG_THRESHOLD_AVERAGE_WIDTH-1-:INTEG_THRESHOLD_AVERAGE_WIDTH]) < $unsigned(INTEG_THRESHOLD_AVERAGE_MIN) 
                             || $unsigned(int_data_wire[INTEG_THRESHOLD_AVERAGE_32_OFFSET*32+INTEG_THRESHOLD_AVERAGE_WIDTH-1-:INTEG_THRESHOLD_AVERAGE_WIDTH]) > $unsigned(INTEG_THRESHOLD_AVERAGE_MAX)
                             || $unsigned(int_data_wire[INTEG_THRESHOLD_AVERAGE_32_OFFSET*32+INTEG_THRESHOLD_AVERAGE_WIDTH-1-:INTEG_THRESHOLD_AVERAGE_WIDTH]) > $unsigned(32767);
  assign integ_window_oob = $unsigned(int_data_wire[INTEG_WINDOW_32_OFFSET*32+INTEG_WINDOW_WIDTH-1-:INTEG_WINDOW_WIDTH]) < $unsigned(INTEG_WINDOW_MIN) 
                         || $unsigned(int_data_wire[INTEG_WINDOW_32_OFFSET*32+INTEG_WINDOW_WIDTH-1-:INTEG_WINDOW_WIDTH]) > $unsigned(INTEG_WINDOW_MAX);
  assign integ_en_oob = $unsigned(int_data_wire[INTEG_EN_32_OFFSET*32+31:INTEG_EN_32_OFFSET*32]) > INTEG_EN_MAX;
  assign boot_test_skip_oob = $unsigned(int_data_wire[BOOT_TEST_SKIP_32_OFFSET*32+BOOT_TEST_SKIP_WIDTH-1:BOOT_TEST_SKIP_32_OFFSET*32]) > BOOT_TEST_SKIP_MAX;
  assign debug_oob = $unsigned(int_data_wire[DEBUG_32_OFFSET*32+DEBUG_WIDTH-1:DEBUG_32_OFFSET*32]) > DEBUG_MAX;
  assign mosi_sck_pol_oob = $unsigned(int_data_wire[MOSI_SCK_POL_32_OFFSET*32+MOSI_SCK_POL_WIDTH-1:MOSI_SCK_POL_32_OFFSET*32]) > MOSI_SCK_POL_MAX;
  assign miso_sck_pol_oob = $unsigned(int_data_wire[MISO_SCK_POL_32_OFFSET*32+MISO_SCK_POL_WIDTH-1:MISO_SCK_POL_32_OFFSET*32]) > MISO_SCK_POL_MAX;

  // Address and value bound compliance sent to write response
  // Send SLVERR if there are any violations
  assign int_bresp_wire = 
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == SYS_EN_32_OFFSET) ? (sys_en_oob ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == CMD_BUF_RESET_32_OFFSET) ? (cmd_buf_reset_oob ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == DATA_BUF_RESET_32_OFFSET) ? (data_buf_reset_oob ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == INTEG_THRESHOLD_AVERAGE_32_OFFSET) ? ((locked || integ_thresh_avg_oob) ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == INTEG_WINDOW_32_OFFSET) ? ((locked || integ_window_oob) ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == INTEG_EN_32_OFFSET) ? ((locked || integ_en_oob) ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == BOOT_TEST_SKIP_32_OFFSET) ? ((locked || boot_test_skip_oob) ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == DEBUG_32_OFFSET) ? ((locked || debug_oob) ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == MOSI_SCK_POL_32_OFFSET) ? ((locked || mosi_sck_pol_oob) ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == MISO_SCK_POL_32_OFFSET) ? ((locked || miso_sck_pol_oob) ? 2'b10 : 2'b00) :
    2'b10;
  
  assign sys_en = int_data_wire[SYS_EN_32_OFFSET*32];

  // Lock violation wire
  // sys_en, cmd_buf_reset, and data_buf_reset are not locked, so they are not checked
  assign int_lock_viol_wire = 
            integ_thresh_avg != int_data_wire[INTEG_THRESHOLD_AVERAGE_32_OFFSET*32+INTEG_THRESHOLD_AVERAGE_WIDTH-1:INTEG_THRESHOLD_AVERAGE_32_OFFSET*32]
            || integ_window != int_data_wire[INTEG_WINDOW_32_OFFSET*32+INTEG_WINDOW_WIDTH-1:INTEG_WINDOW_32_OFFSET*32]
            || integ_en != int_data_wire[INTEG_EN_32_OFFSET*32]
            || boot_test_skip != int_data_wire[BOOT_TEST_SKIP_32_OFFSET*32+BOOT_TEST_SKIP_WIDTH-1:BOOT_TEST_SKIP_32_OFFSET*32]
            || debug != int_data_wire[DEBUG_32_OFFSET*32+DEBUG_WIDTH-1:DEBUG_32_OFFSET*32]
            || mosi_sck_pol != int_data_wire[MOSI_SCK_POL_32_OFFSET*32]
            || miso_sck_pol != int_data_wire[MISO_SCK_POL_32_OFFSET*32];

  // Configuration register sanitization logic
  always @(posedge aclk)
  begin
    if(!aresetn)
    begin
      int_bvalid_reg <= 1'b0;
      int_rvalid_reg <= 1'b0;
      int_rdata_reg <= {(AXI_DATA_WIDTH){1'b0}};

      cmd_buf_reset <= {CMD_BUF_RESET_WIDTH{1'b1}}; // Command buffer reset is high if reset is asserted, but defaults to 0 otherwise
      data_buf_reset <= {DATA_BUF_RESET_WIDTH{1'b1}}; // Data buffer reset is high if reset is asserted, but defaults to 0 otherwise
      integ_thresh_avg <= INTEG_THRESHOLD_AVERAGE_DEFAULT_CAPPED;
      integ_window <= INTEG_WINDOW_DEFAULT_CAPPED;
      integ_en <= INTEG_EN_DEFAULT_CAPPED;
      boot_test_skip <= BOOT_TEST_SKIP_DEFAULT_CAPPED;
      debug <= DEBUG_DEFAULT_CAPPED;
      mosi_sck_pol <= MOSI_SCK_POL_DEFAULT_CAPPED;
      miso_sck_pol <= MISO_SCK_POL_DEFAULT_CAPPED;

      locked <= 1'b0;
      lock_viol <= 1'b0;
    end
    else
    begin
      int_bvalid_reg <= int_bvalid_next;
      int_rvalid_reg <= int_rvalid_next;
      int_rdata_reg <= int_rdata_next;

      // Buffers are a register even though they're not locked to allow the reset value to be different than the default
      cmd_buf_reset <= int_data_wire[CMD_BUF_RESET_32_OFFSET*32+CMD_BUF_RESET_WIDTH-1:CMD_BUF_RESET_32_OFFSET*32];
      data_buf_reset <= int_data_wire[DATA_BUF_RESET_32_OFFSET*32+DATA_BUF_RESET_WIDTH-1:DATA_BUF_RESET_32_OFFSET*32];

      // Lock other registers if sys_en is set
      if(sys_en) begin
        locked <= 1'b1;
        integ_thresh_avg <= int_data_wire[INTEG_THRESHOLD_AVERAGE_32_OFFSET*32+INTEG_THRESHOLD_AVERAGE_WIDTH-1:INTEG_THRESHOLD_AVERAGE_32_OFFSET*32];
        integ_window <= int_data_wire[INTEG_WINDOW_32_OFFSET*32+INTEG_WINDOW_WIDTH-1:INTEG_WINDOW_32_OFFSET*32];
        integ_en <= int_data_wire[INTEG_EN_32_OFFSET*32+INTEG_EN_WIDTH-1:INTEG_EN_32_OFFSET*32];
        boot_test_skip <= int_data_wire[BOOT_TEST_SKIP_32_OFFSET*32+BOOT_TEST_SKIP_WIDTH-1:BOOT_TEST_SKIP_32_OFFSET*32];
        debug <= int_data_wire[DEBUG_32_OFFSET*32+DEBUG_WIDTH-1:DEBUG_32_OFFSET*32];
        mosi_sck_pol <= int_data_wire[MOSI_SCK_POL_32_OFFSET*32];
        miso_sck_pol <= int_data_wire[MISO_SCK_POL_32_OFFSET*32];
      end else if (unlock) begin
        locked <= 1'b0;
        lock_viol <= 1'b0;
      end

      // Check for lock violations if locked
      if(locked) begin
        if(int_lock_viol_wire) begin
          lock_viol <= 1'b1;
        end
      end

    end
  end

  // Write response logic
  always @*
  begin
    int_bvalid_next = int_bvalid_reg;

    if(int_wvalid_wire)
    begin
      int_bvalid_next = 1'b1;
      s_axi_bresp = int_bresp_wire;
    end

    if(s_axi_bready & int_bvalid_reg)
    begin
      int_bvalid_next = 1'b0;
      s_axi_bresp = 2'b0;
    end
  end

  // Read data mux
  always @*
  begin
    int_rvalid_next = int_rvalid_reg;
    int_rdata_next = int_rdata_reg;

    if(s_axi_arvalid)
    begin
      int_rvalid_next = 1'b1;
      int_rdata_next = int_data_mux[s_axi_araddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB]];
    end

    if(s_axi_rready & int_rvalid_reg)
    begin
      int_rvalid_next = 1'b0;
    end
  end

  // Assign S_AXI signals
  assign s_axi_rresp = 2'd0;
  assign s_axi_awready = int_wvalid_wire;
  assign s_axi_wready = int_wvalid_wire;
  assign s_axi_bvalid = int_bvalid_reg;
  assign s_axi_arready = 1'b1;
  assign s_axi_rdata = int_rdata_reg;
  assign s_axi_rvalid = int_rvalid_reg;

endmodule
