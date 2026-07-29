# Example 05: Device Driver

Example 05 shows how to reach the same PL registers as the earlier examples, at
the same speed, but through a proper Linux **device driver** instead of
`/dev/mem` -- so the userspace program **does not need root**.

The project introduces the following tools and concepts:
- Why `/dev/mem` register access is fast but requires root
- Writing a small platform driver that binds to a device-tree node
- Exposing registers to userspace with a **misc device** and `mmap`
- Getting a non-root device node with no udev rule (`miscdevice.mode`)
- How the build automation wires the block design, device tree, kernel module,
  and software together

## Overview

Examples 02-04 talk to the PL registers by opening `/dev/mem` and `mmap`-ing a
physical address (`0x40000000`, ...). That works and it is fast, but it has two
problems:

1. **It requires root.** `/dev/mem` is a window onto *all* of physical memory,
   so the kernel only hands it to `root`. Any program that touches a register
   has to run as root (or be given `CAP_SYS_RAWIO`).
2. **It hardcodes addresses.** The physical address lives in the C source, so
   if the block moves in the hardware design, the software has to change too.

This example keeps the *exact same hardware* -- one `CFG -> NAND -> STS` block,
the same round-trip test as ex02 -- and swaps out *how userspace reaches it*.
A tiny kernel module, `simple-reg`, binds to the block via the device tree and
publishes it as `/dev/simple-reg`. Userspace opens that node (no root) and
`mmap`s it, and from then on the access is a plain pointer load/store, exactly
as fast as the `/dev/mem` version.

The key insight: **`mmap` is what makes `/dev/mem` fast, and `mmap` is
available through a normal driver too.** The speed never came from `/dev/mem`
specifically -- it came from mapping the registers into the process's page
tables so there is no syscall per access. A driver can do the same mapping
while scoping access to *only these registers* and setting a permissive mode on
its own device node.

## The software change: before and after

Both programs live in `software/`. They are written to be as close to
line-for-line identical as possible.

| | `reg-mem-test` (before) | `reg-test` (after) |
|---|---|---|
| Device opened | `/dev/mem` | `/dev/simple-reg` |
| Needs root? | **Yes** | **No** |
| CFG mapping | `mmap(..., fd, 0x40000000)` | `mmap(..., fd, 0)` (region 0) |
| STS mapping | `mmap(..., fd, 0x40100000)` | `mmap(..., fd, PAGE_SIZE)` (region 1) |
| Physical address in source? | Yes (`0x40000000`) | No |
| Register access | `cfg[0] = a; sts[0]` | `cfg[0] = a; sts[0]` (identical) |
| Speed | full (no per-access syscall) | full (identical) |

Everything after the `mmap` calls -- writing the two CFG words, reading the STS
NAND result, the benchmark loop -- is byte-for-byte the same. Only the device
you open and the `mmap` *offset* change.

### The mmap offset is a region selector, not an address

In the `/dev/mem` version the `mmap` offset is the real physical address. In the
driver version it is a small **region selector** defined by the driver:

- offset `0` -> region 0 -> `"cfg"` (`0x40000000` in the PL)
- offset `PAGE_SIZE` -> region 1 -> `"sts"` (`0x40100000` in the PL)

The driver looks at `vma->vm_pgoff` (the offset in pages), picks the matching
region, and maps *its* real physical pages. Userspace never names `0x40000000`
anywhere. If the block moves in `block_design.tcl`, only the device tree
changes; `reg-test.c` is untouched.

## The driver: `simple-reg`

Source: `examples/kernel_modules/simple-reg/petalinux/simple-reg.c` (symlinked
into `kernel_modules/simple-reg`). It is intentionally small -- about 200 lines
including its teaching comments -- and does three things.

### 1. It binds to the hardware via the device tree

`simple-reg` is a **platform driver** with

```c
.compatible = "zynq-toolbox,simple-reg"
```

The device tree overlay (`cfg/.../petalinux/2024.2/device_tree.dtsi`) declares a
node with that `compatible` string and two named register windows:

```dts
&amba_pl {
  simple_reg: simple-reg@40000000 {
    compatible = "zynq-toolbox,simple-reg";
    reg = <0x40000000 0x1000>,   /* cfg */
          <0x40100000 0x1000>;   /* sts */
    reg-names = "cfg", "sts";
  };
};
```

When the kernel sees a device-tree node whose `compatible` matches a driver, it
calls that driver's `probe`. This is the binding: the *device tree* says where
the registers are, the *driver* says what to do with them. Neither one hardcodes
the other.

> Note: PetaLinux's device-tree generator already emits an auto-node for every
> PL IP, but with a `compatible` no driver matches -- so those stay unbound and
> claim nothing. Our node with the private `zynq-toolbox,simple-reg` compatible
> is the only one that gets a driver, and the two coexist harmlessly.

### 2. It claims the registers and publishes a non-root node

In `probe`, for each named region the driver calls
`platform_get_resource_byname(pdev, IORESOURCE_MEM, "cfg" / "sts")` to learn the
physical address from the device tree, then `devm_request_mem_region(...)` to
**take ownership** of it. This is the thing `/dev/mem` never does: two drivers
can no longer fight over the same registers.

It then registers a **misc device**:

```c
sr->misc.minor = MISC_DYNAMIC_MINOR;
sr->misc.name  = "simple-reg";     /* -> /dev/simple-reg */
sr->misc.fops  = &simple_reg_fops;
sr->misc.mode  = 0660;             /* group-accessible: no root, no udev rule */
misc_register(&sr->misc);
```

`misc.mode = 0660` is the whole reason this works without root. The misc core
creates `/dev/simple-reg` with that mode directly -- **no udev rule required**,
which matters here because this rootfs has no udev to install rules into. Any
user in the node's group can `open` it.

### 3. It maps registers to userspace with `mmap` (and only `mmap`)

The driver implements exactly one file operation, `mmap`:

```c
static int simple_reg_mmap(struct file *file, struct vm_area_struct *vma)
{
    struct miscdevice *misc = file->private_data;
    struct simple_reg_dev *sr = container_of(misc, struct simple_reg_dev, misc);
    unsigned long index = vma->vm_pgoff;              /* region selector */
    ...
    vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);   /* MMIO: uncached */
    return io_remap_pfn_range(vma, vma->vm_start,
                              r->phys >> PAGE_SHIFT, len, vma->vm_page_prot);
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

Nothing in this example is wired up by hand at boot. Each piece is picked up by
the standard build scripts:

1. **Block design** (`block_design.tcl`) builds the single `CFG -> NAND -> STS`
   block at `0x40000000` / `0x40100000`. This ends up in the bitstream and the
   `.xsa` hardware definition.

2. **Device tree** (`cfg/.../petalinux/2024.2/device_tree.dtsi`) adds the
   `simple-reg` node with the private `compatible` and `reg-names`. The
   `compatible` string is what *binds the driver to the hardware*; the
   `reg-names` are what the driver looks up by name.

3. **Kernel module** (`kernel_modules/simple-reg`, a symlink to
   `examples/kernel_modules/simple-reg`) is discovered automatically by
   `scripts/petalinux/kernel_modules.sh`, which:
   - runs `petalinux-create modules --name simple-reg`,
   - copies the module's source into the generated recipe,
   - adds any extra source files to the recipe's `SRC_URI` (so multi-file
     modules build -- `simple-reg` is single-file, but the mechanism is there),
   - appends `KERNEL_MODULE_AUTOLOAD += "simple-reg"` so the module is loaded
     **automatically at boot** (writes `/etc/modules-load.d/simple-reg.conf`).

4. **Software** (`software/reg-test`, `software/reg-mem-test`) is cross-compiled
   and dropped into the rootfs by the software build script. Each directory has
   a top `.c` file matching the directory name; the per-directory `Makefile` is
   generated automatically.

So a normal `make` produces an SD image where `simple-reg` is already loaded,
`/dev/simple-reg` already exists at mode `0660`, and both test programs are on
the `PATH`.

> Autoload note: enabling autoload-by-default in `kernel_modules.sh` applies to
> *every* module a project ships, not just `simple-reg`. For the example modules
> (`dummy-kmod`, `u-dma-buf`) this is harmless, but be aware of it if you add a
> module you do *not* want loaded at boot.

## Trying it on hardware

After building and booting (do this yourself when you're ready -- builds are not
run for you):

1. **Confirm the driver bound and claimed its regions:**

   ```sh
   dmesg | grep simple-reg
   ```

   You should see one line per region (`region 0 "cfg"...`, `region 1 "sts"...`)
   and a final `/dev/simple-reg ready (mode 0660), 2 regions`.

2. **Confirm the node is non-root:**

   ```sh
   ls -l /dev/simple-reg
   # crw-rw---- 1 root <group> ... /dev/simple-reg
   ```

3. **Run the driver test as an ordinary user (no sudo):**

   ```sh
   reg-test
   ```

   It should print the six NAND round-trip vectors as `ok`, a benchmark line,
   and `All checks passed.`

4. **Compare against the `/dev/mem` baseline (this one needs root):**

   ```sh
   sudo reg-mem-test
   ```

   Same NAND results, and a benchmark within noise of `reg-test` -- proving the
   driver path is not slower, just root-free.

## PetaLinux

The default configuration is changed to make the packaged image EXT4 format to
load from an SD card, and the `simple-reg` kernel module is built out-of-tree
and set to autoload at boot (see the build-automation section above).
