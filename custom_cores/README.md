***Updated 2025-07-01***
# Custom cores

This directory contains the Verilog source code for custom IP cores for use in projects' Vivado block design flow. Vivado uses packaged IP as cells in the block design, which need to be created from code in this directory as part of the build process (see the `cores` target in the top level Makefile and README).

## Vendors

Cores are separated into directories by "vendor", which is the name of the person or organization that created the core (this is partially to handle licensing differences between cores, if some come with a GNU or MIT license).

Each vendor directory contains a `info/vendor_info.json` file that contains information about the vendor that Vivado uses when packaging the cores (vendor display name and vendor URL).

Each vendor directory contains a [`cores`](#cores) directory that contains the actual cores, as well as an optional `shared_submodules` directory that contains submodules symlinked between multiple cores (mainly to avoid file renaming issues with symlinks).

## Cores

Within a vendor directory (e.g. `lcb`), cores are stored under the `cores` directory. Each core has its own top Verilog file. The core directory, top verilog `.v` file, and module name should all match. Cores can also include any additional Verilog files in the `cores/[core_name]/submodules` directory, which will be packaged with the top module. 

### Interface ports

Packaged cores can include Vivado interface ports (e.g. AXI4 or BRAM). These are primarily inferred, but can be annotated. To infer the port, the cores are expected to have the same port names as the interface ports in the Vivado IP catalog in order to infer the correct interface, like in the following example:

```verilog
// AXI4-Lite subordinate interface
input  wire [AXI_ADDR_WIDTH-1:0]   s_axi_awaddr,  // AXI4-Lite slave: Write address
input  wire                        s_axi_awvalid, // AXI4-Lite slave: Write address valid
output wire                        s_axi_awready, // AXI4-Lite slave: Write address ready
input  wire [AXI_DATA_WIDTH-1:0]   s_axi_wdata,   // AXI4-Lite slave: Write data
input  wire [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,   // AXI4-Lite slave: Write strobe
input  wire                        s_axi_wvalid,  // AXI4-Lite slave: Write data valid
output wire                        s_axi_wready,  // AXI4-Lite slave: Write data ready
output reg  [1:0]                  s_axi_bresp,   // AXI4-Lite slave: Write response
output reg                         s_axi_bvalid,  // AXI4-Lite slave: Write response valid
input  wire                        s_axi_bready,  // AXI4-Lite slave: Write response ready
input  wire [AXI_ADDR_WIDTH-1:0]   s_axi_araddr,  // AXI4-Lite slave: Read address
input  wire                        s_axi_arvalid, // AXI4-Lite slave: Read address valid
output wire                        s_axi_arready, // AXI4-Lite slave: Read address ready
output reg  [AXI_DATA_WIDTH-1:0]   s_axi_rdata,   // AXI4-Lite slave: Read data
output reg  [1:0]                  s_axi_rresp,   // AXI4-Lite slave: Read data response
output reg                         s_axi_rvalid,  // AXI4-Lite slave: Read data valid
input  wire                        s_axi_rready,  // AXI4-Lite slave: Read data ready
```

Some interfaces (like BRAM) require some additional annotation, like:

```verilog
// BRAM port
(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 bram_porta CLK" *)
output wire                         bram_porta_clk,
(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 bram_porta RST" *)
output wire                         bram_porta_rst,
(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 bram_porta ADDR" *)
output wire [BRAM_ADDR_WIDTH-1:0]   bram_porta_addr,
(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 bram_porta DIN" *)
output wire [BRAM_DATA_WIDTH-1:0]   bram_porta_wdata,
(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 bram_porta WE" *)
output wire [BRAM_DATA_WIDTH/8-1:0] bram_porta_we
```

## Tests

Each core can include a `tests` directory that contains testbench files for the core. These are not used in the Vivado block design flow, but can be used to test the core in simulation using cocotb. This document covers the directory structure for writing tests. For information on how to run tests, see the **Testing** section in the top level README.

The `tests` directory needs to contain a `src` directory that contains the source testbench files. Inside the `src` directory, there is one required file, which needs to be named `testbench.py`. This should import `cocotb` and have tests with the decorator `@cocotb.test()`. Please read the [cocotb documentation](https://docs.cocotb.org/en/stable/) for more information on how to write tests.

If the core has Verilog parameters, the `tests/src` directory can optionally contain the file `parameters.json`, which can define values for those parameters. For example:
```json
{
  "DATA_WIDTH": 16,
  "ADDR_WIDTH": 4,
  "ALMOST_FULL_THRESHOLD": 2,
  "ALMOST_EMPTY_THRESHOLD": 2
}
```

Additionally, the `tests/src` directory can contain any other Python files, which can be imported and used by the `testbench.py` file. The test results are marked in the Makefile as dependent on all files in the `tests/src` directory, so any changes to these files will trigger a rebuild of the tests when running `make tests`.
