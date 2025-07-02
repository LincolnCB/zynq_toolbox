***TODO OUT OF DATE -- IN PROGRESS***

---

# Example 02: AXI Interface

Example 02 is a demonstration of some basic AXI interfaces.

The project introduces the following tools and concepts:
- Tcl scripting for block design creation
- Tcl scripting for submodules
- Custom block design cores
- AXI memory interfaces and mapping
- BRAM block sizes and usage
- Utilization reports

## Overview


## Software


## Tools and Concepts

### Tcl Scripting for Block Design Creation

### Tcl Scripting for Submodules

### Custom Block Design Cores

### AXI Memory Interfaces and Mapping

### BRAM Block Sizes and Usage

### Utilization Reports




## TODO: Previous text (to be removed)

The project also supports simple code demonstrating the use of just the AXI hub's config and status registers. The project implements a NAND gate that takes two 32-bit inputs from the AXI hub's config register and outputs the result to the status register. This is a useful project to demonstrate how to interface with the AXI hub's registers from both the programmable logic (PL) and the processing system (PS) of the Zynq.

## Block Design

The project's block design (`block_design.tcl`) goes as follows:
- Initialize the processing system, externalizing the fixed IO and RAM connections (`DDR`). The PS is initialized based off of the default value for the given board, with the AXI ACP disabled. The PS's Manager AXI port 0 clock is sourced from the PS's FPGA interface clock `FCLK_CLK0`.
- Instantiate the AXI hub. The hub takes the clock from `FCLK_CLK0` and reset from a reset hub. The hub's address is assigned to cover 128M starting from `0x40000000` (needs to go to `0x47FFFFFF` to cover all ports). The port is chosen by setting the bits here: `0x4*000000` to 0 for CFG, 1, for STS, and 2-7 for ports 0-5. Each port has more memory range than it could feasibly use (BRAM is capped at 140 blocks of 36Kib, which comes out to a max of 4.5KiB). 
- Instantiate a FIFO loopback module using the separate `fifo.tcl` script. This module has an `axis_fifo_sync` from `cores/lcb` alongside some port management to get a reset from a 32-bit cfg port and concatenate status signals into a 32-bit port. This makes for the simplest access. This module is connected to the AXI hub port 0. The FIFO requires BRAM blocks (140 available). Any size up to 1024 will use 1 block, while anything above will use 2 blocks.
- Instantiate a BRAM interface module that allows for read and write access to the BRAM on port 1. This module is also managed by the AXI hub on port 1. The BRAM also requires 1 BRAM block (of the 140 available) for each 1024 write depth if the width is 32 bits.
- Finally the code uses the first 64 CFG register bits to implement a simple NAND gate. The inputs are the first two 32-bit CFG registers, and the output is the first 32 bits of the STS register. The NAND operation is done in the `nand.tcl` module, and the STS result is concatenated with the other status signals from the FIFO loopback module.

## C Code

There are two C code examples in the `software` folder. The first is a simple test of the AXI hub's config and status registers (`reg_test.c`). The second is a more complex example that uses the FIFO and BRAM interfaces (`hub_test.c`).

### Reg Test

The C code demonstrates writes and reads to the CFG and STS registers. It first does example writes of different sizes to the CFG register, reading back the full register to demonstrate. Then, it performs write operations to the CFG register in 32-bit and 64-bit chunks, comparing the result read fromt the STS register to the expected value.

### Hub Test

The C code alows for writes and reads to the FIFO and BRAM. It opens `/dev/mem` to access the memory interfaces for each port. The base address for each port/register is `0x4*000000`, with `*` equal to 0 for CFG, 1 for STS, and 2-7 for ports 0-5. From there, the code works as a playground, just handling inputs and parsing commands, and will run read/write/reset commands as needed. Use `help` as a command after running the script to see the commands.

## PetaLinux

The default configuration is changed to make the packaged image EXT4 format to load from an SD card. 
