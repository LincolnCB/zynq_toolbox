***Updated 2026-08-06***

# Example 01: Basics

Example 01 is the first full project in this repo, and exists mostly to walk through the shape of a build rather than to do anything complicated in the PL. It stands up a bare Zynq processing system (no custom AXI logic), boots a full PetaLinux image from an SD card, and ships one small userspace program that reprograms the FPGA fabric clock (`FCLK0`) at runtime.

If you're new to the repo, start here: everything after this example assumes you already understand the `cores -> xpr -> xsa -> petalinux -> sd` pipeline that this README lays out.

The project introduces the following tools and concepts:
- The overall project structure and where each piece lives
- Board files and how a project declares support for a board/version
- Building the Vivado project file (`.xpr`)
- Building the Vivado hardware definition (`.xsa`)
- Building a bootable PetaLinux SD image
- The `Makefile` and the build scripts it drives
- Automatic inclusion of C software into the rootfs
- Controlling the `FCLK0` clock from software via the SLCR registers

## Overview

There is deliberately almost nothing in the programmable logic here. `block_design.tcl` initializes the Zynq processing system (PS) from the board preset, disables the AXI interfaces it does not need, and routes `FCLK_CLK0` out to a top-level port so the clock exists in the design. That is the entire hardware design.

The interesting part is the flow: the same `make` invocation turns that tiny block design into a bitstream, wraps it in an `.xsa`, builds a PetaLinux system around it, cross-compiles the C program in `software/`, and writes an SD image where that program is already on the `PATH`. Every later example reuses this exact flow and just adds more to the PL, the rootfs, or the software.

## Tools and Concepts

### Project structure and organization

A project is a folder under `projects/` and is defined mainly by its `block_design.tcl`. Beyond that it declares board support under `cfg/[board]/[board_ver]/` and can add optional folders (`software/`, `modules/`, `cores/`, `kernel_modules/`, `rootfs_include/`). See the top-level [projects README](../README.md) for the full list and the helper Tcl procedures (`init_ps`, `cell`, `wire`, `addr`, `module`).

### Board files and board support

The PS preset, pin map, and part number all come from the board files under `boards/[board]/board_files/[board_ver]/`. A project only supports a board/version if it has a matching `cfg/[board]/[board_ver]/` directory. This example ships `snickerdoodle_black/1.0` and `sdrlab_122_16/1.0`.

### Building the Vivado project file (`.xpr`)

`make xpr` runs the Vivado scripts to create just the project (`tmp/[board]/[board_ver]/ex01_basics/project.xpr`) without building anything downstream. This is the fastest way to open the design in the Vivado GUI and poke at the block design.

### Building the hardware definition (`.xsa`)

`make xsa` builds the bitstream and exports the `.xsa` hardware handoff that PetaLinux consumes. The `.xsa` carries the PS configuration (including the `FCLK0` setup) that the bootloader needs.

### Building a bootable PetaLinux SD image

`make sd` (the default target) runs the full pipeline and produces the `BOOT`/`RootFS` payloads under `out/[board]/[board_ver]/ex01_basics/`. `make write_sd` copies them to a mounted card.

### The Makefile and build scripts

The top-level `Makefile` orchestrates the `cores -> xpr -> xsa -> petalinux -> sd` stages, delegating to the scripts under `scripts/`. Intermediates land in `tmp/`; final outputs in `out/`. See the top-level [README](../../README.md) for the full target list.

### Automatic software inclusion

Every folder under `software/` is cross-compiled and dropped into the rootfs automatically, producing a binary named after the folder (here, `fclk-control`). The top-level C file must match the folder name (`fclk-control.c`); the per-directory `Makefile` is generated for you.

### Controlling the FCLK clock from software

Covered under [Software](#software): unlock the SLCR, rewrite the `FPGA0_CLK_CTRL` dividers, re-lock.

## Software

`software/fclk-control/fclk-control.c` is a small interactive program that changes the `FCLK0` frequency while Linux is running. 

**This is probably more detail than is helpful for a first project.** I'm mainly including it in this project as an arbitrary demonstration of user-space software -- while `hello-world.c` might be better, I also needed somewhere to put this program for my own documentation of how to manage the system clock at runtime. Don't worry about the details of this one if you find it too much. However, it does illustrate the general approach of reaching important registers through `/dev/mem` and using `mmap()` to get a pointer to the memory-mapped region.

The Zynq generates `FCLK0` by dividing an internal PLL through two 6-bit dividers, configured in the `FPGA0_CLK_CTRL` register inside the System Level Control Registers (SLCR) at `0xF8000000`. The SLCR block is write-protected, so the program:

1. `mmap`s the SLCR page through `/dev/mem` (this needs root)
2. writes the unlock code (`0xDF0D`) to the SLCR unlock register
3. reads/writes the two dividers in `FPGA0_CLK_CTRL` (each `1`-`63`)
4. writes the lock code (`0x767B`) back

At the prompt you enter a divider number (`0` or `1`) and a value, and it reprograms the clock live. The resulting frequency is `PLL / (div0 * div1)`; on the Snickerdoodle the source PLL is 2 GHz, so e.g. `div0=7, div1=1` gives ~285 MHz and larger products slow it down toward the ~250 kHz floor.

## PetaLinux configuration

The only change from the PetaLinux defaults (`cfg/.../petalinux/2024.2/config.patch`) is switching the rootfs to EXT4 on SD (`CONFIG_SUBSYSTEM_ROOTFS_EXT4`, root on `/dev/mmcblk0p2`) instead of the default RAM disk, so the image boots from the card.

## Trying it on hardware

After building and booting:

```sh
sudo fclk-control
```

Enter e.g. `0 7` then `1 2` to divide the clock down, and scope `FCLK0` (or observe downstream logic in a later example) to confirm the frequency changes. Root is required because the program reaches the SLCR through `/dev/mem`.

---

Next: [Example 02: AXI Interface](../ex02_axi_interface/README.md)

