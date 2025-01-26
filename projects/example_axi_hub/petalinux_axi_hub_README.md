# Example AXI Hub Ports

Ths project demonstrates the full use of the AXI hub, utilizing the CFG/STS registers and both AXI-Stream and BRAM ports. The AXI hub can support either a BRAM or AXI-Stream interface on each port, where the AXI-Stream can include the Manager, Subordinate, or both. The project instantiates a AXI-Stream FIFO loopback on port 0. The FIFO takes input from the hub port 0 AXI-S Manager, and outputs to the hub port 0 AXI-S Subordinate, allowing read and write on port 0. The project then includes a BRAM interface on port 1 with both read and write access.

## Block Design

The project's block design (`block_design.tcl`) goes as follows:
- Initialize the processing system, externalizing the fixed IO and RAM connections (`DDR`). The PS's Manager AXI port 0 clock is sourced from the PS's FPGA interface clock `FCLK_CLK0`
- Instantiate the AXI hub. The hub takes the clock from `FCLK_CLK0` and reset from a reset hub. The hub's address is assigned to cover 128M starting from `0x40000000` (needs to go to `0x47FFFFFF` to cover all ports). The port is chosen by setting the bits here: `0x4*000000` to 0 for CFG, 1, for STS, and 2-7 for ports 0-5. Each port has more memory range than it could feasibly use (BRAM is capped at 140 blocks of 36Kib, which comes out to a max of 4.5KiB). 
- Instantiate a FIFO loopback module using the separate `fifo.tcl` script. This module has an `axis_fifo_sync` from `cores/lcb` alongside some port management to get a reset from a 32-bit cfg port and concatenate status signals into a 32-bit port. This makes for the simplest access. This module is connected to the AXI hub port 0. The FIFO requires BRAM blocks (140 available). Any size up to 1024 will use 1 block, while anything above will use 2 blocks.
- Instantiate a BRAM interface module that allows for read and write access to the BRAM on port 1. This module is also managed by the AXI hub on port 1. The BRAM also requires 1 BRAM block (of the 140 available) for each 1024 write depth if the width is 32 bits. 

## C Code

The C code alows for writes and reads to the FIFO and BRAM. It opens `/dev/mem` to access the memory interfaces for each port. The base address for each port/register is `0x4*000000`, with `*` equal to 0 for CFG, 1 for STS, and 2-7 for ports 0-5. From there, the code just handles inputs, parses commands, and will run read/write/reset commands as needed. Use `help` as a command after running the script to see the commands.
