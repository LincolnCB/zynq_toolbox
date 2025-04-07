# Cores

This directory contains custom IP cores for use in Vivado's block design build flow. These cores are used in the projects in the `projects/` directory. Cores are separated by "vendor", which is the name of the person or organization that created the core (this is partially to handle licensing differences between cores, which are all open-source but variably restrictive in terms of GNU vs MIT).

Each vendor directory contains a `info/vendor_info.json` file that contains information about the vendor that Vivado uses when packaging the cores (vendor display name and vendor URL). Otherwise, all the cores are just Verilog files that are parsed into cores. For interface ports (e.g. AXI4), the cores are expected to have the same port names as the interface ports in the Vivado IP catalog in order to infer the correct interface. Some interfaces like BRAM require some additional annotation, like:

```verilog
(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 bram_porta CLK" *)
output wire                         bram_porta_clk,
(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 bram_porta RST" *)
output wire                         bram_porta_rst,
```
