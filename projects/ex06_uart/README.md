***Updated 2026-08-25***

# Example 06: UART

Example 06 brings up a second serial port by routing the Zynq's `UART1` controller out through the PS MIO pins. There is no custom PL at all -- the entire change lives in the processing system configuration -- so it shows how PS peripheral settings flow from the block design, through the `.xsa`, and into the booted Linux system as a working `/dev/ttyPS1`.

The project introduces the following tools and concepts:
- Configuring PS peripherals (MIO pin assignment) from `block_design.tcl`
- How PS settings travel via the `.xsa` rather than the bitstream
- Getting a second console/serial device (`/dev/ttyPS1`) in Linux
- MIO pull-up configuration
- PetaLinux configuration of the PS options

## Overview

`block_design.tcl` initializes the PS from the board preset and then enables `UART1`, mapping it to MIO pins 36-37 with pull-ups enabled:

```tcl
init_ps ps {
  PCW_USE_M_AXI_GP0 0
  PCW_USE_S_AXI_ACP 0
  PCW_UART1_PERIPHERAL_ENABLE 1
  PCW_UART1_UART1_IO {MIO 36 .. 37}
  PCW_MIO_36_PULLUP enabled
  PCW_MIO_37_PULLUP enabled
} {}
```

Note here that MIO/peripheral configuration is not part of the bitstream -- it is applied by the first-stage bootloader from data carried in the `.xsa`. If you're used to approaches where you can just swap a bitstream, this is where that approach wouldn't work for these style of projects; you have to rebuild the PetaLinux boot files so the bootloader configures `UART1`.

## Tools and Concepts

### Configuring PS peripherals from Tcl

The `init_ps` helper loads the board preset and then applies the `PCW_*` overrides you pass it. Enabling a peripheral and pinning it to MIO is done entirely through these properties. The easiest way to discover the right property names is to open the PS customization GUI in Vivado (`make xpr`, then open the block design in Vivado), set the peripheral visually under *Peripheral I/O Pins*, and copy the `set_property` lines Vivado echoes.

### PS settings travel in the `.xsa`, not the bitstream

Because peripheral I/O is brought up by the bootloader, the settings ride along in the `.xsa` hardware handoff and are baked into the boot image PetaLinux builds. This is why a PS-config change requires a full rebuild (`make sd`) and don't allow a simple bitstream swap.

### A second serial device in Linux

Once `UART1` is enabled and the boot files are rebuilt, Linux exposes it as `/dev/ttyPS1` (the primary console remains `/dev/ttyPS0`). Nothing in the rootfs needs to change to *have* the device; it appears because the hardware description says the controller is enabled.

## PetaLinux configuration

The config patch switches the rootfs to EXT4 on SD so the image boots from the card (same as the other examples). The `UART1` device itself comes from the PS configuration in the `.xsa`, not from a rootfs or device-tree change in this project.

> Note: `UART1` comes up as a plain serial device, not as the login console. If you want a shell on it (or a specific baud), that is a further PetaLinux serial-settings / bootargs change on top of this example.

## Trying it on hardware

Wire a 3.3 V UART adapter to the MIO 36/37 pins for `UART1`, boot, and from the main console:

```sh
ls -l /dev/ttyPS*          # /dev/ttyPS0 (console) and /dev/ttyPS1 should both exist
stty -F /dev/ttyPS1 115200 # set a baud rate
echo hello > /dev/ttyPS1   # should appear on the adapter
```

Seeing `/dev/ttyPS1` confirms the PS peripheral configuration made it all the way from `block_design.tcl` to the running kernel.

---

Previous: [Example 05: DMA](../ex05_dma/README.md)

