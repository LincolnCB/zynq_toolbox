`timescale 1 ns / 1 ps

module axi_shim_cfg #
(
  parameter integer AXI_ADDR_WIDTH = 16,

  // Trigger lockout (+0)
  parameter integer TRIGGER_LOCKOUT_DEFAULT = 250000, // 1 ms at 250MHz

  // Calibration offset (+4)
  parameter integer CALIBRATION_OFFSET_DEFAULT = 0,

  // DAC divider (+8)
  parameter integer DAC_DIVIDER_DEFAULT = 1000,

  // Integrator threshold average (+12)
  parameter integer INTEGRATOR_THRESHOLD_AVERAGE_DEFAULT = 16384,
  
  // Integrator window (+16)
  parameter integer INTEGRATOR_WINDOW_DEFAULT = 5000000, // 100 ms at 50MHz

  // Integrator enable default
  parameter integer INTEG_EN_DEFAULT = 1
)
(
  // System signals
  input  wire                       aclk,
  input  wire                       aresetn,

  input  wire                       unlock,

  // Configuration outputs
  output reg  [31:0]         trig_lockout,
  output reg  [15:0]         cal_offset,
  output reg  [15:0]         dac_divider,
  output reg  [14:0]         integ_thresh_avg,
  output reg  [31:0]         integ_window,
  output reg                 integ_en,
  output wire                sys_en,

  // Configuration bounds
  output wire  trig_lockout_oob,
  output wire  cal_offset_oob,
  output wire  dac_divider_oob,
  output wire  integ_thresh_avg_oob,
  output wire  integ_window_oob,
  output wire  integ_en_oob,
  output wire  sys_en_oob,
  output reg   lock_viol,

  // AXI4-Line subordinate port
  input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_awaddr,  // AXI4-Lite subordinate: Write address
  input  wire                       s_axi_awvalid, // AXI4-Lite subordinate: Write address valid
  output wire                       s_axi_awready, // AXI4-Lite subordinate: Write address ready
  input  wire [31:0]                s_axi_wdata,   // AXI4-Lite subordinate: Write data
  input  wire [3:0]                 s_axi_wstrb,   // AXI4-Lite subordinate: Write strobe
  input  wire                       s_axi_wvalid,  // AXI4-Lite subordinate: Write data valid
  output wire                       s_axi_wready,  // AXI4-Lite subordinate: Write data ready
  output wire [1:0]                 s_axi_bresp,   // AXI4-Lite subordinate: Write response
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

  // Localparams for MIN/MAX values
  localparam integer TRIGGER_LOCKOUT_MIN = 0;
  localparam integer TRIGGER_LOCKOUT_MAX = 32'hFFFFFFFF; // 32-bit unsigned max
  localparam integer CALIBRATION_OFFSET_MIN = -2048;
  localparam integer CALIBRATION_OFFSET_MAX = 2048;
  localparam integer DAC_DIVIDER_MIN = 200;
  localparam integer DAC_DIVIDER_MAX = 16'hFFFF; // 16-bit unsigned max
  localparam integer INTEGRATOR_THRESHOLD_AVERAGE_MIN = 1;
  localparam integer INTEGRATOR_THRESHOLD_AVERAGE_MAX = 15'h7FFF; // 15-bit unsigned max
  localparam integer INTEGRATOR_WINDOW_MIN = 2048;
  localparam integer INTEGRATOR_WINDOW_MAX = 32'hFFFFFFFF; // 32-bit unsigned max

  // Localparams for bit ranges
  localparam integer TRIGGER_LOCKOUT_32_OFFSET = 0;
  localparam integer CALIBRATION_OFFSET_32_OFFSET = 1;
  localparam integer DAC_DIVIDER_32_OFFSET = 2;
  localparam integer INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET = 3;
  localparam integer INTEGRATOR_WINDOW_32_OFFSET = 4;
  localparam integer INTEGRATOR_EN_32_OFFSET = 5;
  localparam integer SYS_EN_32_OFFSET = 6;

  localparam integer TRIGGER_LOCKOUT_WIDTH = 32;
  localparam integer CALIBRATION_OFFSET_WIDTH = 16;
  localparam integer DAC_DIVIDER_WIDTH = 16;
  localparam integer INTEGRATOR_THRESHOLD_AVERAGE_WIDTH = 15;
  localparam integer INTEGRATOR_WINDOW_WIDTH = 32;

  // Local capped default values
  localparam integer TRIGGER_LOCKOUT_DEFAULT_CAPPED = 
    (TRIGGER_LOCKOUT_DEFAULT < TRIGGER_LOCKOUT_MIN) ? TRIGGER_LOCKOUT_MIN :
    (TRIGGER_LOCKOUT_DEFAULT > TRIGGER_LOCKOUT_MAX) ? TRIGGER_LOCKOUT_MAX :
    TRIGGER_LOCKOUT_DEFAULT;

  localparam integer CALIBRATION_OFFSET_DEFAULT_CAPPED = 
    (CALIBRATION_OFFSET_DEFAULT < CALIBRATION_OFFSET_MIN) ? CALIBRATION_OFFSET_MIN :
    (CALIBRATION_OFFSET_DEFAULT > CALIBRATION_OFFSET_MAX) ? CALIBRATION_OFFSET_MAX :
    CALIBRATION_OFFSET_DEFAULT;

  localparam integer DAC_DIVIDER_DEFAULT_CAPPED = 
    (DAC_DIVIDER_DEFAULT < DAC_DIVIDER_MIN) ? DAC_DIVIDER_MIN :
    (DAC_DIVIDER_DEFAULT > DAC_DIVIDER_MAX) ? DAC_DIVIDER_MAX :
    DAC_DIVIDER_DEFAULT;

  localparam integer INTEGRATOR_THRESHOLD_AVERAGE_DEFAULT_CAPPED = 
    (INTEGRATOR_THRESHOLD_AVERAGE_DEFAULT < INTEGRATOR_THRESHOLD_AVERAGE_MIN) ? INTEGRATOR_THRESHOLD_AVERAGE_MIN :
    (INTEGRATOR_THRESHOLD_AVERAGE_DEFAULT > INTEGRATOR_THRESHOLD_AVERAGE_MAX) ? INTEGRATOR_THRESHOLD_AVERAGE_MAX :
    INTEGRATOR_THRESHOLD_AVERAGE_DEFAULT;

  localparam integer INTEGRATOR_WINDOW_DEFAULT_CAPPED = 
    (INTEGRATOR_WINDOW_DEFAULT < INTEGRATOR_WINDOW_MIN) ? INTEGRATOR_WINDOW_MIN :
    (INTEGRATOR_WINDOW_DEFAULT > INTEGRATOR_WINDOW_MAX) ? INTEGRATOR_WINDOW_MAX :
    INTEGRATOR_WINDOW_DEFAULT;

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

  reg locked;

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

  // Initial values
  assign int_data_wire = int_axi_data_wire | (~int_data_modified_wire & int_initial_data_wire);
  assign int_initial_data_wire = {
    {(CFG_DATA_WIDTH/32 - 6){32'b0}},
    INTEG_EN_DEFAULT,
    INTEGRATOR_WINDOW_DEFAULT_CAPPED,
    INTEGRATOR_THRESHOLD_AVERAGE_DEFAULT_CAPPED,
    DAC_DIVIDER_DEFAULT_CAPPED,
    CALIBRATION_OFFSET_DEFAULT_CAPPED,
    TRIGGER_LOCKOUT_DEFAULT_CAPPED
  };

  // Out of bounds checks. Use the whole word for the check to avoid truncation
  assign trig_lockout_oob = $unsigned(int_data_wire[TRIGGER_LOCKOUT_32_OFFSET*32+31:TRIGGER_LOCKOUT_32_OFFSET*32]) < $unsigned(TRIGGER_LOCKOUT_MIN) 
                         || $unsigned(int_data_wire[TRIGGER_LOCKOUT_32_OFFSET*32+31:TRIGGER_LOCKOUT_32_OFFSET*32]) > $unsigned(TRIGGER_LOCKOUT_MAX);
  assign cal_offset_oob = $signed(int_data_wire[CALIBRATION_OFFSET_32_OFFSET*32+CALIBRATION_OFFSET_WIDTH-1:CALIBRATION_OFFSET_32_OFFSET*32]) < $signed(CALIBRATION_OFFSET_MIN)
                       || $signed(int_data_wire[CALIBRATION_OFFSET_32_OFFSET*32+CALIBRATION_OFFSET_WIDTH-1:CALIBRATION_OFFSET_32_OFFSET*32]) > $signed(CALIBRATION_OFFSET_MAX)
                       || $signed(int_data_wire[CALIBRATION_OFFSET_32_OFFSET*32+CALIBRATION_OFFSET_WIDTH-1:CALIBRATION_OFFSET_32_OFFSET*32]) < $signed(-32767)
                       || $signed(int_data_wire[CALIBRATION_OFFSET_32_OFFSET*32+CALIBRATION_OFFSET_WIDTH-1:CALIBRATION_OFFSET_32_OFFSET*32]) > $signed(32767);
  assign dac_divider_oob = $unsigned(int_data_wire[DAC_DIVIDER_32_OFFSET*32+DAC_DIVIDER_WIDTH-1:DAC_DIVIDER_32_OFFSET*32]) < $unsigned(DAC_DIVIDER_MIN)
                        || $unsigned(int_data_wire[DAC_DIVIDER_32_OFFSET*32+DAC_DIVIDER_WIDTH-1:DAC_DIVIDER_32_OFFSET*32]) > $unsigned(DAC_DIVIDER_MAX)
                        || $unsigned(int_data_wire[DAC_DIVIDER_32_OFFSET*32+DAC_DIVIDER_WIDTH-1:DAC_DIVIDER_32_OFFSET*32]) > $unsigned(65535);
  assign integ_thresh_avg_oob = $unsigned(int_data_wire[INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32+INTEGRATOR_THRESHOLD_AVERAGE_WIDTH-1:INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32]) < $unsigned(INTEGRATOR_THRESHOLD_AVERAGE_MIN) 
                             || $unsigned(int_data_wire[INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32+INTEGRATOR_THRESHOLD_AVERAGE_WIDTH-1:INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32]) > $unsigned(INTEGRATOR_THRESHOLD_AVERAGE_MAX)
                             || $unsigned(int_data_wire[INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32+INTEGRATOR_THRESHOLD_AVERAGE_WIDTH-1:INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32]) > $unsigned(32767);
  assign integ_window_oob = $unsigned(int_data_wire[INTEGRATOR_WINDOW_32_OFFSET*32+INTEGRATOR_WINDOW_WIDTH-1:INTEGRATOR_WINDOW_32_OFFSET*32]) < $unsigned(INTEGRATOR_WINDOW_MIN) 
                         || $unsigned(int_data_wire[INTEGRATOR_WINDOW_32_OFFSET*32+INTEGRATOR_WINDOW_WIDTH-1:INTEGRATOR_WINDOW_32_OFFSET*32]) > $unsigned(INTEGRATOR_WINDOW_MAX);
  assign integ_en_oob = int_data_wire[INTEGRATOR_EN_32_OFFSET*32+31:INTEGRATOR_EN_32_OFFSET*32] > 1;
  assign sys_en_oob = int_data_wire[SYS_EN_32_OFFSET*32+31:SYS_EN_32_OFFSET*32] > 1;

  // Address and value bound compliance sent to write response
  // Send SLVERR if there are any violations
  assign int_bresp_wire = 
    locked ? 2'b10 :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == TRIGGER_LOCKOUT_32_OFFSET) ? (trig_lockout_oob ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == CALIBRATION_OFFSET_32_OFFSET) ? (cal_offset_oob ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == DAC_DIVIDER_32_OFFSET) ? (dac_divider_oob ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET) ? (integ_thresh_avg_oob ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == INTEGRATOR_WINDOW_32_OFFSET) ? (integ_window_oob ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == INTEGRATOR_EN_32_OFFSET) ? (integ_en_oob ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == SYS_EN_32_OFFSET) ? (sys_en_oob ? 2'b10 : 2'b00) :
    2'b10;
  
  assign sys_en = int_data_wire[SYS_EN_32_OFFSET*32];

  // Configuration register sanitization logic
  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
      int_bvalid_reg <= 1'b0;
      int_rvalid_reg <= 1'b0;
      int_rdata_reg <= {(AXI_DATA_WIDTH){1'b0}};

      trig_lockout <= TRIGGER_LOCKOUT_DEFAULT_CAPPED;
      cal_offset <= CALIBRATION_OFFSET_DEFAULT_CAPPED;
      dac_divider <= DAC_DIVIDER_DEFAULT_CAPPED;
      integ_thresh_avg <= INTEGRATOR_THRESHOLD_AVERAGE_DEFAULT_CAPPED;
      integ_window <= INTEGRATOR_WINDOW_DEFAULT_CAPPED;
      integ_en <= 0;

      locked <= 1'b0;
      lock_viol <= 1'b0;
    end
    else
    begin
      int_bvalid_reg <= int_bvalid_next;
      int_rvalid_reg <= int_rvalid_next;
      int_rdata_reg <= int_rdata_next;

      // Lock the configuration registers
      if(sys_en) begin
        locked <= 1'b1;
        trig_lockout <= int_data_wire[TRIGGER_LOCKOUT_32_OFFSET*32+TRIGGER_LOCKOUT_WIDTH-1:TRIGGER_LOCKOUT_32_OFFSET*32];
        cal_offset <= int_data_wire[CALIBRATION_OFFSET_32_OFFSET*32+CALIBRATION_OFFSET_WIDTH-1:CALIBRATION_OFFSET_32_OFFSET*32];
        dac_divider <= int_data_wire[DAC_DIVIDER_32_OFFSET*32+DAC_DIVIDER_WIDTH-1:DAC_DIVIDER_32_OFFSET*32];
        integ_thresh_avg <= int_data_wire[INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32+INTEGRATOR_THRESHOLD_AVERAGE_WIDTH-1:INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32];
        integ_window <= int_data_wire[INTEGRATOR_WINDOW_32_OFFSET*32+INTEGRATOR_WINDOW_WIDTH-1:INTEGRATOR_WINDOW_32_OFFSET*32];
        integ_en <= int_data_wire[INTEGRATOR_EN_32_OFFSET*32];
      end else if (unlock) begin
        locked <= 1'b0;
        lock_viol <= 1'b0;
      end

      // Check for lock violations if locked
      if(locked) begin
        if(trig_lockout != int_data_wire[TRIGGER_LOCKOUT_32_OFFSET*32+TRIGGER_LOCKOUT_WIDTH-1:TRIGGER_LOCKOUT_32_OFFSET*32] 
          || cal_offset != int_data_wire[CALIBRATION_OFFSET_32_OFFSET*32+CALIBRATION_OFFSET_WIDTH-1:CALIBRATION_OFFSET_32_OFFSET*32]
          || dac_divider != int_data_wire[DAC_DIVIDER_32_OFFSET*32+DAC_DIVIDER_WIDTH-1:DAC_DIVIDER_32_OFFSET*32]
          || integ_thresh_avg != int_data_wire[INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32+INTEGRATOR_THRESHOLD_AVERAGE_WIDTH-1:INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32]
          || integ_window != int_data_wire[INTEGRATOR_WINDOW_32_OFFSET*32+INTEGRATOR_WINDOW_WIDTH-1:INTEGRATOR_WINDOW_32_OFFSET*32]
          || integ_en != int_data_wire[INTEGRATOR_EN_32_OFFSET*32]) begin
          lock_viol <= 1'b1;
        end
      end

    end
  end

  // Write response

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

  assign s_axi_rresp = 2'd0;

  assign s_axi_awready = int_wvalid_wire;
  assign s_axi_wready = int_wvalid_wire;
  assign s_axi_bvalid = int_bvalid_reg;
  assign s_axi_arready = 1'b1;
  assign s_axi_rdata = int_rdata_reg;
  assign s_axi_rvalid = int_rvalid_reg;

endmodule
