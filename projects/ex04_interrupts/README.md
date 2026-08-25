***Updated 2026-08-25***

# Example 04: Interrupts

Example 04 wires custom PL logic into the ARM cores' interrupt controller and delivers those interrupts to userspace **without root**. A CFG register in the PL lets software raise any of eight interrupt lines; the PS receives them on the `IRQ_F2P` port; and a userspace program blocks on a `/dev/user_irqN` misc device to catch each one.

Delivery uses the repo's own `pl-irq` kernel module -- the interrupt sibling of the `pl-reg` register driver from the device-driver example. `pl-irq` binds to the interrupt node by a private device-tree `compatible`, so (unlike the in-tree generic UIO driver) it needs **no kernel command-line parameter** and **no chmod**: it names each device after its Vivado label and creates it mode `0666`. The older generic-UIO-plus-bootargs approach still works and is documented at the end as an alternative.

The project introduces the following tools and concepts:
- Driving the PL-to-PS interrupt lines (`IRQ_F2P`)
- Zynq-7000 interrupt numbering for PL interrupts
- Exposing an interrupt to userspace non-root with the `pl-irq` misc-device module
- Hand-writing a project device-tree fragment (`device_tree.dtsi`)
- Level- vs edge-triggered interrupts
- (Alternative) the in-tree `uio_pdrv_genirq` driver and the kernel-bootarg it requires

## Overview

The PL side is small. A CFG register (`pavel-demin:user:axi_cfg_register`, 64-bit, at `0x40000000`, instance `axi_irq`) is sliced into eight single-bit lines -- four taken from the low word, four from the high word -- and concatenated into the PS `IRQ_F2P` port:

```tcl
cell xilinx.com:ip:xlconcat:2.1 irq_concat { NUM_PORTS 8 } { dout ps/IRQ_F2P }
```

Writing a bit in the CFG register therefore drives the corresponding fabric interrupt. On the Zynq-7000, the sixteen `IRQ_F2P[n]` lines map to shared peripheral interrupts 29-44 (offset by 32 inside the CPU, so they show up as 61+ in `/proc/interrupts`). The eight lines here are given mixed polarities in the device tree so you can compare edge- and level-triggered behavior.

## Delivering interrupts non-root with pl-irq

Two out-of-tree kernel modules do the work, both autoloaded from the project's `kernel_modules/` (symlinks to `examples/kernel_modules/pl-reg` and `.../pl-irq`):

- **pl-reg** claims the CFG register and publishes it as `/dev/axi_irq` (mode `0666`), named from the block's Vivado instance label. Software drives the interrupt bits with a plain `mmap` -- no `/dev/mem`, no `sudo`. This is the same module the device-driver example is built around.

- **pl-irq** claims each interrupt node and publishes it as `/dev/user_irq0`..`/dev/user_irq7` (mode `0666`), again named from the node label. Its userspace contract mirrors UIO: `open`, `write()` a `1` to arm, `poll()`/`read()` to block until the line fires, then clear the source and `write()` `1` to re-arm. The handler masks the line at the GIC on each fire, so a level line delivers exactly one interrupt per pulse.

Because both modules carry their own `of_match_table`, the kernel binds them automatically from the device tree -- there is no kernel command line to maintain and no boot-time `chmod`.

## The device tree

`cfg/.../petalinux/2024.2/device_tree.dtsi` hand-declares one node per interrupt under `&amba_pl`, each bound to `pl-irq` and carrying its GIC interrupt number and trigger type:

```dts
user_irq0: user_irq0 {
  compatible = "zynq-toolbox,pl-irq";
  interrupt-parent = <&intc>;
  interrupts = <0 29 1>;   /* SPI 29, edge (1) */
};
/* ... user_irq2 uses "<0 31 4>" -> level-high (4), etc. */
```

The third cell is the trigger type (`1` = rising edge, `4` = level-high). Mixing them across the eight lines is intentional, to demonstrate the difference in `/proc/interrupts` and in the clear-and-rearm handshake. The CFG register itself needs no node here: `pl-reg` binds it through the compatible PetaLinux auto-generates for the core.

The config patch (`config.patch`) only switches the image to SD/EXT4 -- there is no bootarg edit and no extra kernel option, because `pl-irq` is a module bound by compatible.

## Software

`software/interrupt_test/interrupt_test.c` is a single-threaded, non-root tester:

- it `mmap`s the CFG register through `/dev/axi_irq` (pl-reg) to raise interrupts;
- it opens the eight `/dev/user_irqN` (pl-irq) devices and arms them;
- one `poll()` waits on **stdin and all eight interrupt fds at once** -- a command raises a line, and the same `poll()` wakes on the resulting interrupt, prints it, clears the source bit, and re-arms;
- on startup it runs a **self-test** that pulses each line and confirms the interrupt reaches userspace, printing a per-line pass/fail table.

At the prompt you can `set <n>`, `set_all`, `status`, re-run `test`, or `exit` (`help` lists them). Because `pl-irq` masks a line when it fires, each `set` yields exactly one interrupt regardless of trigger type; the counts should track `/proc/interrupts`.

## Trying it on hardware

After building and booting:

```sh
dmesg | grep -E 'pl-reg|pl-irq'   # both modules bound; /dev/axi_irq + /dev/user_irqN ready (mode 0666)
ls /dev/user_irq*                 # /dev/user_irq0 .. /dev/user_irq7
cat /proc/interrupts | grep pl-irq  # eight GIC lines, ~61-68
interrupt-test                    # no sudo
```

`interrupt-test` runs its self-test first; expect all eight lines to report `ok`. Then `set 2`, `set_all`, and `status` let you fire lines and watch the counts increment in step with `/proc/interrupts`.

## Alternative: generic-uio via the kernel command line

Before `pl-irq`, this example used the kernel's in-tree `uio_pdrv_genirq` driver, which publishes an interrupt node as `/dev/uioN`. It still works and is worth knowing, but it costs more manual maintenance:

- The node's `compatible` must be `"generic-uio"`, and the driver only binds nodes whose compatible matches its `of_id` **module parameter**, which defaults to nothing. So the kernel command line must carry `uio_pdrv_genirq.of_id="generic-uio"`. That is set through the PetaLinux config patch by turning off the auto-generated bootargs and giving an explicit `CONFIG_SUBSYSTEM_USER_CMDLINE`. This edit lives apart from the block design and is easy to drop or overwrite when bootargs are regenerated -- the reason `pl-irq` exists.
- `CONFIG_UIO_PDRV_GENIRQ` must be enabled in the kernel (a `kernel_config.cfg` fragment).
- The `/dev/uioN` node is created root-owned `0600` with no mode knob, so a non-root program needs a boot-time `chmod` (or `sudo`).

> Note from when this example used that path: setting the extra bootarg through the *DTG Settings -> Kernel Bootargs* menu produced malformed quotes in the generated command line and broke the device-tree compile. Setting the full command line explicitly avoided that.

Use the generic-UIO route when you specifically need it (for instance, a feature that genuinely requires kernel-command-line control); otherwise `pl-irq` is the lower-maintenance default used here.

---

Previous: [Example 03: Device Driver](../ex03_device_driver/README.md) | Next: [Example 05: DMA](../ex05_dma/README.md)
