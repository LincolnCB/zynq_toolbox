***Updated 2026-08-06***

# Example 04: Interrupts

Example 04 wires custom PL logic into the ARM cores' interrupt controller and delivers those interrupts to userspace through the kernel's generic UIO driver. A CFG register in the PL lets software raise any of eight interrupt lines; the PS receives them on the `IRQ_F2P` port; and a userspace program blocks on `/dev/uioN` to catch each one. It is the first example to hand-write a device-tree fragment and to configure the kernel.

The project introduces the following tools and concepts:
- Driving the PL-to-PS interrupt lines (`IRQ_F2P`)
- Zynq-7000 interrupt numbering for PL interrupts
- Exposing interrupts to userspace with UIO (`uio_pdrv_genirq`)
- Hand-writing a project device-tree fragment (`device_tree.dtsi`)
- Enabling a kernel option and extra bootargs via the PetaLinux config patch
- Level- vs edge-triggered interrupts

## Overview

The PL side is small. A CFG register (`pavel-demin:user:axi_cfg_register`, 64-bit, at `0x40000000`) is sliced into eight single-bit lines -- four taken from the low word, four from the high word -- and concatenated into the PS `IRQ_F2P` port:

```tcl
cell xilinx.com:ip:xlconcat:2.1 irq_concat { NUM_PORTS 8 } { dout ps/IRQ_F2P }
```

Therefore, writing a bit in the CFG register drives the corresponding fabric interrupt. On the Zynq-7000, the sixteen `IRQ_F2P[n]` lines map to shared peripheral interrupts 29-44 (offset by 32 inside the CPU, so they show up as 61+ in `/proc/interrupts`). The eight lines here are given mixed polarities in the device tree so you can compare edge- and level-triggered behavior.

Delivery to userspace uses UIO: the generic `uio_pdrv_genirq` driver publishes each interrupt node as `/dev/uio0`..`/dev/uio7`. A userspace thread `read()`s a `/dev/uioN` to block until the interrupt fires, and writes back a `1` to re-arm it.

## The device tree

`cfg/.../petalinux/2024.2/device_tree.dtsi` hand-declares one node per interrupt under `&amba_pl`, each bound to the generic UIO driver and carrying its GIC interrupt number and trigger type:

```dts
user_irq0: user_irq0 {
  compatible = "generic-uio";
  interrupt-parent = <&intc>;
  interrupts = <0 29 1>;   /* SPI 29, edge (1) */
};
/* ... user_irq2 uses "<0 31 4>" -> level-high (4), etc. */
```

The third cell is the trigger type (`1` = rising edge, `4` = level-high). Mixing them across the eight lines is intentional, to demonstrate the difference in `/proc/interrupts` and in how the clear-and-rearm handshake behaves.

## Kernel and bootargs configuration

Unlike the earlier examples, the PetaLinux config patch does more than switch to SD/EXT4. It also turns off the auto-generated bootargs and sets an explicit kernel command line that includes `uio_pdrv_genirq.of_id="generic-uio"`, so the generic UIO driver binds to the `compatible = "generic-uio"` nodes above.

The UIO platform driver itself (`CONFIG_UIO_PDRV_GENIRQ`) is enabled as a built-in via the kernel configuration so the nodes are handled at boot with no module to load.

> Note from development: setting the extra bootarg through the *DTG Settings -> Kernel Bootargs* menu produced malformed quotes in the generated command line and broke the device-tree compile. Setting the full command line explicitly (as this patch does) avoids that.

## Software

`software/interrupt_test/interrupt_test.c` is an interactive, multi-threaded tester:

- it `mmap`s the CFG register through `/dev/mem` to raise interrupts (so it needs `sudo`);
- it spawns one thread per line, each blocking on `read("/dev/uioN")` to detect the interrupt and writing `1` back to clear/re-arm it;
- at the prompt you can `set`, `set_mask`, `set_all`, `hard_set`, and `clear*` individual lines or masks (type `help` for the list).

Because the eight lines have different trigger types, setting an edge line pulses once while a level line stays asserted until cleared -- which the tool lets you observe directly.

## Trying it on hardware

After building and booting:

```sh
zcat /proc/config.gz | grep CONFIG_UIO_PDRV_GENIRQ   # expect =y
ls /dev/uio*                                         # /dev/uio0 .. /dev/uio7
cat /proc/interrupts | grep user_irq                 # eight GIC lines, ~61-68
sudo interrupt_test                                  # raise/clear lines interactively
```

Seeing the eight `user_irq` lines in `/proc/interrupts` confirms the PL interrupts reached the GIC, and `interrupt_test` lets you fire them and watch the counts increment.

> Known issue: the level-triggered lines can race in the current C handler (the clear happens outside the detecting thread). Edge lines are solid. This is noted for follow-up and does not affect the edge-triggered demonstration.

---

Previous: [Example 03: UART](../ex03_uart/README.md) | Next: [Example 05: Device Driver](../ex05_device_driver/README.md)

