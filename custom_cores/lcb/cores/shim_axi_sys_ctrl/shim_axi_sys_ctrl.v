`timescale 1 ns / 1 ps

module shim_axi_sys_ctrl #
(
  parameter integer AXI_ADDR_WIDTH = 16,

  // Integrator threshold average (+0)
  parameter integer INTEGRATOR_THRESHOLD_AVERAGE_DEFAULT = 16384,
  
  // Integrator window (+4)
  parameter integer INTEGRATOR_WINDOW_DEFAULT = 5000000, // 100 ms at 50MHz

  // Integrator enable (+8)
  parameter integer INTEG_EN_DEFAULT = 1
)
(
  // System signals
  input  wire                       aclk,
  input  wire                       aresetn,

  input  wire                       unlock,

  // Configuration outputs
  output reg  [14:0]         integ_thresh_avg,
  output reg  [31:0]         integ_window,
  output reg                 integ_en,
  output wire                sys_en,
  output reg  [25:0]         buffer_reset,

  // Configuration bounds
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

  // Localparams for MIN/MAX values
  localparam integer INTEGRATOR_THRESHOLD_AVERAGE_MIN = 1;
  localparam integer INTEGRATOR_THRESHOLD_AVERAGE_MAX = 15'h7FFF; // 15-bit unsigned max
  localparam integer INTEGRATOR_WINDOW_MIN            = 2048;
  localparam integer INTEGRATOR_WINDOW_MAX            = 32'hFFFFFFFF; // 32-bit unsigned max

  // Localparams for bit ranges (shifted after removing DAC divider)
  localparam integer INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET = 0;
  localparam integer INTEGRATOR_WINDOW_32_OFFSET            = 1;
  localparam integer INTEGRATOR_EN_32_OFFSET                = 2;
  localparam integer BUFFER_RESET_32_OFFSET                 = 3;
  localparam integer SYS_EN_32_OFFSET                       = 4;

  localparam integer INTEGRATOR_THRESHOLD_AVERAGE_WIDTH = 15;
  localparam integer INTEGRATOR_WINDOW_WIDTH = 32;
  localparam integer BUFFER_RESET_WIDTH = 26;

  // Local capped default values
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
  assign int_initial_data_wire[INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32+INTEGRATOR_THRESHOLD_AVERAGE_WIDTH-1-:INTEGRATOR_THRESHOLD_AVERAGE_WIDTH] = INTEGRATOR_THRESHOLD_AVERAGE_DEFAULT_CAPPED;
  assign int_initial_data_wire[INTEGRATOR_WINDOW_32_OFFSET*32+INTEGRATOR_WINDOW_WIDTH-1-:INTEGRATOR_WINDOW_WIDTH] = INTEGRATOR_WINDOW_DEFAULT_CAPPED;
  assign int_initial_data_wire[INTEGRATOR_EN_32_OFFSET*32] = INTEG_EN_DEFAULT;
  assign int_initial_data_wire[BUFFER_RESET_32_OFFSET*32+BUFFER_RESET_WIDTH-1-:BUFFER_RESET_WIDTH] = {BUFFER_RESET_WIDTH{1'b0}}; // Buffer reset defaults to 0 (but !aresetn will override them to 1)
  assign int_initial_data_wire[SYS_EN_32_OFFSET*32] = 0;

  // Out of bounds checks. Use the whole word for the check to avoid truncation
  assign integ_thresh_avg_oob = $unsigned(int_data_wire[INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32+INTEGRATOR_THRESHOLD_AVERAGE_WIDTH-1-:INTEGRATOR_THRESHOLD_AVERAGE_WIDTH]) < $unsigned(INTEGRATOR_THRESHOLD_AVERAGE_MIN) 
                             || $unsigned(int_data_wire[INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32+INTEGRATOR_THRESHOLD_AVERAGE_WIDTH-1-:INTEGRATOR_THRESHOLD_AVERAGE_WIDTH]) > $unsigned(INTEGRATOR_THRESHOLD_AVERAGE_MAX)
                             || $unsigned(int_data_wire[INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32+INTEGRATOR_THRESHOLD_AVERAGE_WIDTH-1-:INTEGRATOR_THRESHOLD_AVERAGE_WIDTH]) > $unsigned(32767);
  assign integ_window_oob = $unsigned(int_data_wire[INTEGRATOR_WINDOW_32_OFFSET*32+INTEGRATOR_WINDOW_WIDTH-1-:INTEGRATOR_WINDOW_WIDTH]) < $unsigned(INTEGRATOR_WINDOW_MIN) 
                         || $unsigned(int_data_wire[INTEGRATOR_WINDOW_32_OFFSET*32+INTEGRATOR_WINDOW_WIDTH-1-:INTEGRATOR_WINDOW_WIDTH]) > $unsigned(INTEGRATOR_WINDOW_MAX);
  assign integ_en_oob = int_data_wire[INTEGRATOR_EN_32_OFFSET*32+31:INTEGRATOR_EN_32_OFFSET*32] > 1;
  assign sys_en_oob = int_data_wire[SYS_EN_32_OFFSET*32+31:SYS_EN_32_OFFSET*32] > 1;

  // Address and value bound compliance sent to write response
  // Send SLVERR if there are any violations
  assign int_bresp_wire = 
    locked ? 2'b10 :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET) ? (integ_thresh_avg_oob ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == INTEGRATOR_WINDOW_32_OFFSET) ? (integ_window_oob ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == INTEGRATOR_EN_32_OFFSET) ? (integ_en_oob ? 2'b10 : 2'b00) :
    (s_axi_awaddr[ADDR_LSB+CFG_WIDTH-1:ADDR_LSB] == SYS_EN_32_OFFSET) ? (sys_en_oob ? 2'b10 : 2'b00) :
    2'b10;
  
  assign sys_en = int_data_wire[SYS_EN_32_OFFSET*32];

  // Lock violation wire
  assign int_lock_viol_wire = 
            integ_thresh_avg != int_data_wire[INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32+INTEGRATOR_THRESHOLD_AVERAGE_WIDTH-1:INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32]
            || integ_window != int_data_wire[INTEGRATOR_WINDOW_32_OFFSET*32+INTEGRATOR_WINDOW_WIDTH-1:INTEGRATOR_WINDOW_32_OFFSET*32]
            || integ_en != int_data_wire[INTEGRATOR_EN_32_OFFSET*32];
            // Note: buffer_reset is not checked here, as it can be reset even if locked

  // Configuration register sanitization logic
  always @(posedge aclk)
  begin
    if(!aresetn)
    begin
      int_bvalid_reg <= 1'b0;
      int_rvalid_reg <= 1'b0;
      int_rdata_reg <= {(AXI_DATA_WIDTH){1'b0}};

      integ_thresh_avg <= INTEGRATOR_THRESHOLD_AVERAGE_DEFAULT_CAPPED;
      integ_window <= INTEGRATOR_WINDOW_DEFAULT_CAPPED;
      integ_en <= INTEG_EN_DEFAULT;
      buffer_reset <= {BUFFER_RESET_WIDTH{1'b1}}; // Buffer reset is high if reset is asserted, but defaults to 0 otherwise

      locked <= 1'b0;
      lock_viol <= 1'b0;
    end
    else
    begin
      int_bvalid_reg <= int_bvalid_next;
      int_rvalid_reg <= int_rvalid_next;
      int_rdata_reg <= int_rdata_next;

      // Reset the buffers if requested. Allow this even if locked
      buffer_reset <= int_data_wire[BUFFER_RESET_32_OFFSET*32+BUFFER_RESET_WIDTH-1:BUFFER_RESET_32_OFFSET*32];

      // Lock the configuration registers
      if(sys_en) begin
        locked <= 1'b1;
        integ_thresh_avg <= int_data_wire[INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32+INTEGRATOR_THRESHOLD_AVERAGE_WIDTH-1:INTEGRATOR_THRESHOLD_AVERAGE_32_OFFSET*32];
        integ_window <= int_data_wire[INTEGRATOR_WINDOW_32_OFFSET*32+INTEGRATOR_WINDOW_WIDTH-1:INTEGRATOR_WINDOW_32_OFFSET*32];
        integ_en <= int_data_wire[INTEGRATOR_EN_32_OFFSET*32];
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
