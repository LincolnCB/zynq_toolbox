# Example 05: Device Driver

Example 05 shows how to reach the same PL registers as the earlier examples, at the same speed, but through a proper Linux device driver instead of `/dev/mem` -- so the userspace program doesn't need root/`sudo` permissions, and *without writing any device tree by hand*.

The project introduces the following tools and concepts:
- `/dev/mem` register access is fast and simple but requires root
- Binding a platform driver to the device-tree nodes **PetaLinux auto-generates** for every PL IP (no hand-written `.dtsi`)
- Naming a `/dev` entry after a core's Vivado instance, via the auto-generated `/__symbols__`
- Exposing registers to userspace with a "misc device" and `mmap`
- Getting a non-root device node with no udev rule (`miscdevice.mode`)
- How the build automation wires the block design, kernel module, and software together

## Overview

Examples 02-04 talk to the PL registers by opening `/dev/mem` and `mmap`-ing a physical address (`0x40000000`, ...) defined in the block design. That works and it is fast, but `/dev/mem` is a window onto *all* of physical memory, so the kernel only hands it to `root`. Any program that touches a register has to run as root.

This example keeps the exact same hardware as ex02 -- one `CFG -> NAND -> STS` block -- and reaches it through a driver instead.

A small kernel module, `pl-reg`, binds to the nodes PetaLinux already generates for the two cores and publishes each as its own `/dev` entry named after the core's Vivado instance: **`/dev/cfg`** and **`/dev/sts`**. Userspace opens those (no root) and `mmap`s from there, and from then on the access is a plain pointer load/store, just like the `/dev/mem` version -- but with no root, no hardcoded addresses, and no device-tree file in the project.

## The driver: `pl-reg`

Source: `examples/kernel_modules/pl-reg/petalinux/pl-reg.c` (symlinked into
`kernel_modules/pl-reg`). It is intentionally small and does three things.

### 1. It binds to PetaLinux's auto-generated nodes (no `.dtsi`)

PetaLinux's device-tree generator (DTG) already emits one node per PL IP, with a
`compatible` derived from the core's VLNV (`vendor:library:name:version`). For
ex05's two cores it produces, with no input from us:

```dts
axi_cfg_register@40000000 { compatible = "xlnx,axi-cfg-register-1.0"; reg = <0x40000000 0x1000>; };
axi_sts_register@40100000 { compatible = "xlnx,axi-sts-register-1.0"; reg = <0x40100000 0x1000>; };
```

`pl-reg` is a **platform driver** whose match table lists exactly those
auto-generated compatibles:

```c
static const struct of_device_id pl_reg_of_match[] = {
    { .compatible = "xlnx,axi-cfg-register-1.0" },
    { .compatible = "xlnx,axi-sts-register-1.0" },
    { }
};
```

Because each core is a **separate node**, the kernel calls `probe` once per
node, so the driver produces **one device (and one `/dev` entry) per register
window**. There is no `device_tree.dtsi` anywhere in this project -- the
addresses, the `compatible`, and the names all come from the auto-generated
tree.

> The DTG rewrites the VLNV vendor to `xlnx` and turns underscores into dashes,
> so `pavel-demin:user:axi_cfg_register:1.0` becomes
> `xlnx,axi-cfg-register-1.0`. The `compatible` therefore tracks core **name +
> version**, not vendor. (The full mangling rules, observed from a real build,
> are in the appendix.)

### 2. It names each `/dev` entry from the core's instance name

A `compatible` identifies a core *type*, not a specific instance, so it cannot
by itself say which node is `cfg` and which is `sts` -- and the node *name* is
the shared core name (`axi_cfg_register`), not the instance name either. The
instance identity survives as the **DTS label** the DTG puts on each node
(`cfg: axi_cfg_register@...`), which the device-tree compiler records in the
**`/__symbols__`** node as a label -> path map:

```dts
__symbols__ {
  cfg = "/pl-bus/axi_cfg_register@40000000";
  sts = "/pl-bus/axi_sts_register@40100000";
};
```

> Note: PetaLinux does **not** put PL cores in `/aliases` (that node only holds
> the standard `serial0`/`spi0`/... entries). The Vivado instance name lives in
> `/__symbols__` instead, so that is where the driver looks (falling back to
> `/aliases` first in case a core is ever given a real alias).

In `probe`, the driver reverse-looks-up its own node in `/__symbols__` and names
the misc device after that label -- so the `cfg` and `sts` instances in
`block_design.tcl` become **`/dev/cfg`** and **`/dev/sts`**. No physical address
appears in userspace, and even inside the driver the address only comes from the
node's own `reg` (single-sourced from the block design):

```c
inst = pl_reg_instance_name(dev->of_node);   /* -> "cfg" or "sts" */
strscpy(pr->name, inst ? inst : dev->of_node->name, sizeof(pr->name));
pr->misc.name = pr->name;                     /* -> /dev/cfg, /dev/sts */
```

**Fail-loud property:** if a core's VLNV name or version changes, its
auto-`compatible` changes too, `pl-reg` stops matching, `probe` never runs, and
`/dev/cfg` (or `/dev/sts`) is never created -- so the userspace `open()` fails
with `ENOENT` instead of silently reaching the wrong register. Rename the
instance in the block design and the `/dev` node's name changes with it.

### 3. It claims the registers and maps them to userspace with `mmap`

In `probe` the driver fetches the node's single `reg` window by **index**
(auto-nodes have no `reg-names`), then `devm_request_mem_region(...)` to **take
ownership** of it -- the thing `/dev/mem` never does, so two drivers can no
longer fight over the same registers. It then registers a **misc device**:

```c
res = platform_get_resource(pdev, IORESOURCE_MEM, 0);   /* by index, not name */
devm_request_mem_region(dev, res->start, resource_size(res), "pl-reg");
...
pr->misc.minor = MISC_DYNAMIC_MINOR;
pr->misc.name  = pr->name;      /* -> /dev/cfg or /dev/sts */
pr->misc.mode  = 0666;          /* world-accessible: no root, no udev rule */
misc_register(&pr->misc);
```

`misc.mode = 0666` is the whole reason this works without root. The misc core
creates the node with that mode directly -- **no udev rule required**, which
matters here because this rootfs has no udev to install rules into.

Why `0666` and not `0660`? The misc core creates the node owned `root:root` and
can only set its *mode*, not its *group* -- assigning a friendlier group is a
udev job, and this rootfs has no udev. With `0660` the node stays `root:root`
and a login user who is **not** in the `root` group is denied (`Permission
denied` on `open`). `0666` makes the node world-readable/writable, which is the
only udev-free way to reach it without root. Access is still scoped to *only*
this one register window, never all of physical memory the way `/dev/mem` is.

The driver implements exactly one file operation, `mmap`, mapping the single
window at offset 0:

```c
static int pl_reg_mmap(struct file *file, struct vm_area_struct *vma)
{
    struct pl_reg_dev *pr = container_of(..., struct pl_reg_dev, misc);
    if (vma->vm_pgoff != 0) return -EINVAL;                     /* one window */
    vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);    /* MMIO: uncached */
    return io_remap_pfn_range(vma, vma->vm_start,
                              pr->phys >> PAGE_SHIFT, len, vma->vm_page_prot);
}
```

`io_remap_pfn_range` installs page-table entries that point straight at the
register's physical pages -- the *same* mechanism `/dev/mem` uses. After `mmap`
returns, the kernel is out of the loop entirely: every register access is a
single load/store, no syscall. That is why the benchmark matches `/dev/mem`.

There is deliberately **no** `read`/`write`/`ioctl` path. Those would cost a
syscall per access -- the slow thing we are escaping -- and they would make the
"how do I port my `/dev/mem` code" story more than a one-line change.

### Why not UIO?

UIO is the usual "userspace driver" answer, and it also gives you `mmap`. It is
not used here because its device nodes (`/dev/uioN`) come up `root`-only and the
only supported way to relax that is a udev rule -- which this rootfs cannot
install. A misc device with `.mode` gets us non-root access with no udev, so it
is the simpler fit for the goal of this example.

## How the build automation ties it together

Nothing in this example is wired up by hand at boot -- and, unlike a typical
driver, there is **no device-tree step at all**. Each piece is picked up by the
standard build scripts:

1. **Block design** (`block_design.tcl`) builds the single `CFG -> NAND -> STS`
   block at `0x40000000` / `0x40100000`. This ends up in the bitstream and the
   `.xsa` hardware definition, and the DTG turns each core into a node
   automatically.

2. **Device tree: none.** There is no `cfg/.../petalinux/.../device_tree.dtsi`
   in this project. `pl-reg` binds to the nodes PetaLinux generates from the
   `.xsa`, and takes the `/dev` names from the auto-generated `/__symbols__`
   (the Vivado instance labels). (The build script treats a missing
   device-tree file as "nothing to add".)

3. **Kernel module** (`kernel_modules/pl-reg`, a symlink to
   `examples/kernel_modules/pl-reg`) is discovered automatically by
   `scripts/petalinux/kernel_modules.sh`, which:
   - runs `petalinux-create modules --name pl-reg`,
   - copies the module's source into the generated recipe,
   - adds any extra source files to the recipe's `SRC_URI` (so multi-file
     modules build -- `pl-reg` is single-file, but the mechanism is there),
   - appends `KERNEL_MODULE_AUTOLOAD += "pl-reg"` so the module is loaded
     **automatically at boot** (writes `/etc/modules-load.d/pl-reg.conf`).

4. **Software** (`software/reg-driver`, `software/reg-mem`) is cross-compiled
   and dropped into the rootfs by the software build script. Each directory has
   a top `.c` file matching the directory name; the per-directory `Makefile` is
   generated automatically.

So a normal `make` produces an SD image where `pl-reg` is already loaded,
`/dev/cfg` and `/dev/sts` already exist at mode `0666`, and both test programs
are on the `PATH`.

> Autoload note: enabling autoload-by-default in `kernel_modules.sh` applies to
> *every* module a project ships, not just `pl-reg`. For the example modules
> (`dummy-kmod`, `u-dma-buf`) this is harmless, but be aware of it if you add a
> module you do *not* want loaded at boot.

## Trying it on hardware

After building and booting (do this yourself when you're ready -- builds are not
run for you):

1. **Confirm the driver bound to both nodes:**

   ```sh
   dmesg | grep pl-reg
   ```

   You should see one line per bound node, e.g. `/dev/cfg ready (mode 0666):
   0x40000000 size 0x1000, compatible "xlnx,axi-cfg-register-1.0"` and the same
   for `/dev/sts`.

2. **Confirm the nodes exist and are non-root:**

   ```sh
   ls -l /dev/cfg /dev/sts
   # crw-rw-rw- 1 root root ... /dev/cfg
   # crw-rw-rw- 1 root root ... /dev/sts
   ```

3. **Run the driver test as an ordinary user (no sudo):**

   ```sh
   reg-driver
   ```

   It should print the six NAND round-trip vectors as `ok`, a benchmark line,
   and `All checks passed.`

4. **Compare against the `/dev/mem` baseline (this one needs root):**

   ```sh
   sudo reg-mem
   ```

   Same NAND results, and a benchmark within noise of `reg-driver` -- proving
   the driver path is not slower, just root-free and address-free. The two
   programs (`software/reg-driver` vs `software/reg-mem`) are written to be read
   side by side: identical open/mmap/deref structure, differing only in *what*
   they open and whether they need root.

## PetaLinux

The default configuration is changed to make the packaged image EXT4 format to
load from an SD card, and the `pl-reg` kernel module is built out-of-tree and
set to autoload at boot (see the build-automation section above).

## Appendix: what PetaLinux auto-generates for PL IP (and how `pl-reg` binds to it)

This example's driver (`pl-reg`, above) binds directly to the nodes PetaLinux's
device-tree generator (DTG) emits for each PL IP, with no hand-written device
tree. This appendix records exactly what that auto-generated tree looks like,
based on a real build (`tmp/snickerdoodle_black/1.0/rev_d_shim`, PetaLinux
2024.2), so the binding rules `pl-reg` relies on are grounded in observed
output. It closes with the **alternative** design -- an explicit hand-written
node -- which is what earlier revisions of this example shipped.

### Where it lives

- Auto-generated source: `.../petalinux/components/plnx_workspace/device-tree/device-tree/pl.dtsi`
- Final runtime tree: `.../images/linux/system.dtb` (inspect with `dtc -I dtb -O dts system.dtb`)

### How each PL IP is mangled into a node

For every entry in the Vivado address map the DTG emits one node under the
`pl-bus` node (labelled `amba_pl`, `compatible = "simple-bus"`). For example the
rev_d_shim system control, status, and per-channel FIFO cores came out as:

```dts
axi_sys_ctrl@40000000 {
    compatible = "xlnx,axi-sys-ctrl-1.0";
    reg = <0x40000000 0x80>;
    clock-names = "aclk";
    clocks = <&clkc 15>;          /* FCLK0 */
};
axi_sts_register@40100000 {
    compatible = "xlnx,axi-sts-register-1.0";
    reg = <0x40100000 0x200>;
    ...
};
axi_fifo_bridge@80030000 {        /* one of nine identical-type bridges */
    compatible = "xlnx,axi-fifo-bridge-1.0";
    reg = <0x80030000 0x80>;
    ...
};
```

Three rules, all observed directly in the build:

1. **Node name = `<core-name>@<hex-base-address>`.** The `<core-name>` is the
   *name* field of the IP's VLNV (`vendor:library:`**`name`**`:version`), with
   underscores kept. Every instance of the *same* core shares this name stem and
   is distinguished only by its `@address`. So all nine FIFO bridges are named
   `axi_fifo_bridge@...`.

2. **`compatible = "xlnx,<core-name-with-dashes>-<version>"`.** Two surprises
   here: the vendor is **always rewritten to `xlnx`** (the real vendors `shim`,
   `base`, `pavel-demin` all disappear), and underscores in the name become
   dashes. So `base:user:axi_fifo_bridge:1.0` becomes
   `xlnx,axi-fifo-bridge-1.0`. The `compatible` therefore encodes **core name +
   version only**, not vendor.

3. **`reg = <base size>`** comes straight from the `addr` assignment in
   `block_design.tcl` (`0x40000000 128` -> `reg = <0x40000000 0x80>`). Each node
   also gets `clocks`/`clock-names` for the AXI clock. The DTG does **not** emit
   `reg-names`, so a driver binding to an auto-node must look up regions by
   index, not by name.

### The identity problem, and how `/__symbols__` solves it

A `compatible` identifies a core *type*, not a specific instance, so it cannot
tell `dac_fifo_3` from `adc_fifo_0` -- both are `xlnx,axi-fifo-bridge-1.0`. The
node name (`axi_fifo_bridge`) is shared too; only the `@address` differs.

The instance identity is preserved elsewhere, but **not** in `/aliases` -- that
node only carries the standard `serial0`/`spi0`/... entries, none of the PL
cores. Instead the DTG emits each core's **Vivado instance name** (hierarchical,
flattened with underscores) as the **DTS label** on its node:

```dts
status_reg:                              axi_sts_register@40100000 { ... };
axi_spi_interface_dac_fifo_3_axi_bridge: axi_fifo_bridge@80030000 { ... };
```

The device-tree compiler is run with `-@`, so it preserves every label in a
**`/__symbols__`** node as a label -> path map, which is what survives to
runtime (observed in the built `system.dtb`):

```dts
__symbols__ {
    status_reg                              = "/pl-bus/axi_sts_register@40100000";
    axi_sys_ctrl                            = "/pl-bus/axi_sys_ctrl@40000000";
    spi_clk_snoop                           = "/pl-bus/axi_clock_timing_snoop@40200000";
    axi_spi_interface_dac_fifo_3_axi_bridge = "/pl-bus/axi_fifo_bridge@80030000";
    /* ...one per labelled node, including non-PL labels like clkc... */
};
```

This is the key result: the friendly instance name **survives to runtime**. It
is readable both from the kernel (walk the `/__symbols__` node) and from
userspace at `/proc/device-tree/__symbols__/<name>` or
`/sys/firmware/devicetree/base/__symbols__/<name>`. So PL cores *can* be
addressed by instance name, with the base address only ever used as an internal
tiebreaker (and even that is read from the DT's own `reg`, still single-sourced
from the block design).

### Binding a driver straight to the auto-nodes (no project dtsi)

Combining the above is exactly what `pl-reg` does:

- list the auto-generated compatibles (for ex05,
  `xlnx,axi-cfg-register-1.0` and `xlnx,axi-sts-register-1.0`; for a project
  like rev_d_shim also `xlnx,axi-fifo-bridge-1.0`, ...) in its `of_match_table`;
- in `probe`, recover its node's instance name (reverse-lookup in
  `/__symbols__`, with `/aliases` tried first) and name its misc device after it;
- expose `mmap` at offset 0.

Userspace then does `open("/dev/cfg")` + `mmap(..., 0)` -- **no base address
anywhere in userspace, and nothing added to the block design or a dtsi**,
because the `reg`, `compatible`, and instance label are all auto-emitted. For a
single-instance core the name is short and clean (`/dev/cfg`, `/dev/status_reg`);
for a repeated core it is the long path-style name
(`/dev/axi_spi_interface_dac_fifo_3_axi_bridge`) unless the driver shortens it or
a one-line `label` override is added.

**Fail-loud behavior:** if a core's VLNV name or version changes, its
auto-`compatible` changes, the driver no longer matches, the node stays unbound,
and the `/dev/<name>` node is never created -- so the userspace `open()` fails
with `ENOENT` instead of silently touching the wrong register. Two caveats: the
`compatible` ignores vendor (a different-vendor core of the same name+version
would still match), and interrupt/UIO nodes are **not** auto-emitted this way --
in rev_d_shim the `hw_manager_irq` `generic-uio` node is hand-written in its
`device_tree.dtsi`, so dropping the dtsi applies to register windows, not to
that interrupt.

### Alternative: the explicit hand-written node

Earlier revisions of this example took the opposite approach: instead of binding
to the auto-nodes, the driver declared a *private* `compatible` and the project
shipped a `cfg/.../petalinux/2024.2/device_tree.dtsi` that hand-wrote a single
node grouping both windows under named `reg` regions:

```dts
&amba_pl {
  simple_reg: simple-reg@40000000 {
    compatible = "zynq-toolbox,simple-reg";   /* private: only our driver matches */
    reg = <0x40000000 0x1000>,                /* "cfg" */
          <0x40100000 0x1000>;                /* "sts" */
    reg-names = "cfg", "sts";
  };
};
```

The driver then matched `zynq-toolbox,simple-reg`, looked the windows up **by
name** (`platform_get_resource_byname(..., "cfg"/"sts")`), and exposed both from
one device (`/dev/simple-reg`) using the `mmap` offset as a region selector
(region 0 = cfg, region 1 = sts). The auto-generated nodes still existed, but
since no driver matched *their* `compatible` they stayed unbound and harmless.

**Trade-off.** The explicit node is more robust and self-documenting: a private
`compatible` that can't be broken by a core version bump, named `reg` windows,
and one logical device that can group several scattered windows -- at the cost of
restating every address in a dtsi and keeping it in sync with the block design.
The auto-node approach this example now uses removes that dtsi entirely and
auto-scales to repeated cores (every FIFO bridge binds with no per-instance
markup), at the cost of coupling the driver to the DTG's `xlnx,<name>-<version>`
strings and losing `reg-names` and multi-window grouping. Which is preferable
depends on whether you value the explicit contract or the zero-boilerplate
auto-enumeration.
