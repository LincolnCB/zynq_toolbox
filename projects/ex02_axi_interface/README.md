***Updated 2026-08-25***

# Example 02: AXI Interface

Example 02 is where the PL starts doing real work. It builds four AXI-mapped blocks the PS can read and write over `/dev/mem`: a config (CFG) register, a status (STS) register, a synchronous FIFO, and a block of BRAM. On top of those it wires a trivial vector-NAND so you can check the CFG->PL->STS round trip.

It is the first example to use Tcl scripting in earnest -- custom cores, reusable sub-modules, explicit AXI address assignment -- so most of what later projects do in the block design is introduced here.

The project introduces the following tools and concepts:
- Tcl scripting for the block design
- Reusable block-design sub-modules (`modules/`)
- Instantiating custom (non-Xilinx) cores
- AXI4-Lite register access and explicit address mapping
- A synchronous FIFO behind AXI
- BRAM sizing and how block usage rounds
- Reading the Vivado utilization reports

## Overview

The PS talks to four things through a single `M_AXI_GP0` port fanned out by an AXI SmartConnect:

| Port | Core | Address | Purpose |
|------|------|---------|---------|
| M00 | `pavel-demin:user:axi_cfg_register` (96-bit) | `0x40000000` | PS -> PL config word |
| M01 | `pavel-demin:user:axi_sts_register` (64-bit) | `0x41000000` | PL -> PS status word |
| M02 | `fifo` module (`cores/base` FIFO) | `0x42000000` | PS<->PL FIFO loopback |
| M03 | `axi_bram_ctrl` + `blk_mem_gen` | `0x43000000` | PS<->PL BRAM |

The low bits of the CFG/STS words drive a vector-NAND (`modules/nand.tcl`): CFG bits `63:0` are two 32-bit operands, and their bitwise NAND appears in STS bits `31:0`. CFG bits `95:64` are sliced off to control the FIFO (reset plus flags), and the FIFO status is concatenated into the upper STS bits. Nothing leaves the chip -- there are no external FPGA ports -- so this runs on any supported board without pin constraints.

## Software

Two programs live in `software/`, both reaching the registers through `/dev/mem` (so both need `sudo`).

### `reg-test`

A self-checking demonstration of the CFG/STS path. It writes operand pairs into the CFG register in 32- and 64-bit chunks, reads the NAND result back from STS, and compares against the expected value. Note that the hub's data register is 32 bits wide, so writes should be done in 32-bit (or wider) units.

### `mem-test`

An interactive playground for the FIFO and BRAM ports. It `mmap`s each port's base address (`0x42000000` FIFO, `0x43000000` BRAM) and parses read/write/reset commands so you can push and pop the FIFO and read/write BRAM by hand. Run it and type `help` for the command list.

## Tools and Concepts

### Tcl scripting for the block design

`block_design.tcl` builds the whole design with the helper procedures from `scripts/vivado/project.tcl` (`init_ps`, `cell`, `wire`, `addr`, `module`). A good way to learn these is to do something in the Vivado GUI, copy the Tcl it echoes to the console, and fold it back into the script. `make xpr` builds just the project so you can open it and explore.

### Reusable sub-modules

`modules/fifo.tcl` and `modules/nand.tcl` are self-contained block-design fragments instantiated with the `module` procedure. A module can declare its own internal pins (`create_bd_pin`) and even instantiate several cores, which keeps `block_design.tcl` readable and lets a block be reused across projects. The FIFO module bundles the FIFO core with the slicing/concatenation glue for its control and status words.

### Custom cores

Much of the structure of this repo is heavily inspired by and directly forked from [Pavel Demin](https://github.com/pavel-demin)'s [Red Pitaya Notes](http://pavel-demin.github.io/red-pitaya-notes/) repo. In particular, I use a lot of his tools for scripting the packaging and inclusion of custom cores in the Vivado build process.

The CFG and STS registers are Pavel's cores under `cores/pavel-demin/`, instantiated by VLNV (Vendor, Library, Name, Version, e.g. `pavel-demin:user:axi_cfg_register:1.0`, etc. -- you can omit version usually) just like a Xilinx IP. Every project pulls in non-Xilinx logic this way. You can have multiple user folders under `cores/` and add your own IP there. In this example, I've symlinked the `pavel-demin` folder from the `examples/cores` directory just as a way to reduce duplication across example projects, but you should feel free to make your own cores in your own projects.

Vendor cores are structured in a particular way, which it would be good to read about in the [`examples/cores/README.md`](../../examples/cores/README.md) file. The short version is that each vendor folder contains a `vendor_info.json` with required `display_name` and `url` fields for Vivado core packaging. Then, each core is one folder named after the core, with a top-level verilog file that matches the folder name. These can contain submodules and unit tests, which you should read about in the README above.

### AXI mapping with `addr`

Each subordinate is given an explicit address with the `addr` procedure rather than Vivado auto-assignment, for clarity and repeatability. Offsets are spaced generously (`0x40000000`, `0x41000000`, ...) so each window clears both the 128-byte Vivado minimum and the 4 KiB memory page size, which matters when userspace `mmap`s a page at a time.

### FIFO and BRAM sizing

Both the FIFO and the BRAM consume Zynq block-RAM primitives (140 available on the 7020). Usage rounds up to whole 36 Kib blocks: a FIFO up to 1024 deep uses one block, and BRAM uses roughly one block per 1024 words of 32-bit depth -- crossing a boundary by a single word bumps the count. The BRAM here is `32 x 16384` (512 Kib -> 16 blocks). If you resize it, update the `addr` range to match.

### Utilization reports

After a build, the utilization reports land under `tmp_reports/[board]/[board_ver]/...`. They are the authoritative way to confirm how many BRAM blocks (and other resources) the design actually used, e.g. after changing the FIFO or BRAM depth.

## PetaLinux configuration

The only change from the PetaLinux defaults is switching the rootfs to EXT4 on SD so the image boots from the card. No custom device tree or kernel module is needed -- everything is reached through `/dev/mem`.

## Trying it on hardware

After building and booting:

```sh
sudo reg-test      # self-checking NAND round trip through CFG/STS
sudo mem-test      # interactive FIFO/BRAM playground; type "help"
```

`reg-test` should report matching NAND results. In `mem-test`, push a few words into the FIFO and pop them back, and write/read BRAM addresses, to confirm both AXI ports. Both need root because they use `/dev/mem`; ex03 revisits this same hardware without that requirement.

---

Previous: [Example 01: Basics](../ex01_basics/README.md) | Next: [Example 03: Device Driver](../ex03_device_driver/README.md)

