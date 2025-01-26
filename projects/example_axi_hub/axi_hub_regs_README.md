# Example AXI Hub Registers

This is an example project demonstrating the use of the AXI hub's config and status registers. The project implements a NAND gate that takes two 32-bit inputs from the AXI hub's config register and outputs the result to the status register. This is a useful project to demonstrate how to interface with the AXI hub's registers from both the programmable logic (PL) and the processing system (PS) of the Zynq.


## Block Design

The project's block design (`block_design.tcl`) goes as follows:
- Initialize the the processing system. Here, the Manager AXI port clock is sourced from the PS's FPGA interface clock `FCLK_CLK0`.
- Run board automation to automatically connect all the PS's fixed IO and RAM connections (`DDR`).
- Create a reset hub that can generate a reset signal that the AMD Xilinx tools will handle correctly. The hub is connected to a constant 0 and outputs a constant 1 to `peripheral_aresetn`.
- Instantiate and connect Pavel's AXI hub. Set the CFG data width to 64 bits, and STS to 32. We'll use the CFG to store the input and STS as the place to grab the output. To set the address, use the TCL procedure `addr` (defined in `scripts/vivado/project.tcl`) with base `0x40000000` and range `128M` (goes to `0x47FFFFFF` to fully cover the AXI hub). The CFG and STS might need to be 32-bit multiples.
- Use port slicers and vector logic blocks to run a quick NAND between each half of the CFG register, and output to the STS register.

## C Code

The C code demonstrates a successful NAND write and read, both with two individual 32-bit writes and with a single concatenated 64-bit write. To access them, we open `/dev/mem` and use `mmap` at specific addresses. As noted above, the AXI hub is located at `0x40000000` (defined first by the limits of the AXI GP0 port on the Zynq and then by our choice of address within those limits in `block_design.tcl`). Bits 24-26 set the part of the hub: 0 is CFG, 1 is STS. We can then write and read relative to those base addresses. 
