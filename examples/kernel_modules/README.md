***Updated 2026-08-25***
# Kernel modules

This directory contains source code for custom kernel modules that can be added to the Linux kernel built from PetaLinux. They're picked up by the `scripts/petalinux/kernel_modules.sh` script, which builds every module directory found under a project's `kernel_modules/` folder. To add one to a project, place (or symlink) the module directory under
```
projects/[project_name]/kernel_modules/
```

These modules are built "out-of-tree" and included in the PetaLinux build. The build also enables `KERNEL_MODULE_AUTOLOAD` for each module, so they load automatically at boot -- you don't need to `modprobe` or `insmod` them by hand.

## Modules here

- `u-dma-buf` — physically-contiguous DMA buffers exposed to userspace (upstream `ikwzm/udmabuf`).
- `pl-reg` — non-root, `mmap`-only access to a PL AXI register window, bound automatically by device-tree compatible (ex03). No hand-written device tree, no root.
- `pl-irq` — the interrupt sibling of `pl-reg`: non-root, doorbell (`poll`/`read`/`write`) access to a PL interrupt line, bound by device-tree compatible. Publishes a `0666` misc device (`/dev/<label>`), so unlike the in-tree `generic-uio` it needs no `uio_pdrv_genirq` kernel command line and no `chmod` (ex04).
- `dummy-kmod` — minimal skeleton module for reference.

## Kernel module directory structure

Each directory in this directory is its own kernel module. The name of the directory is the name of the kernel module. Each module directory can contain extra files for clarity (`README.md` or any general documentation or source files), but primarily contains a `petalinux/` directory

Within this directory, the source code is composed of a kernel `Makefile`, a top-level `.c` C file, and any other `.c` files needed for the module. These files should work the same as any type of kernel source code.

### Example kernel module added

For instance, getting the `u-dma-buf` kernel module from its [GitHub repo](https://github.com/ikwzm/udmabuf/tree/master), I directly copied the `Makefile` and `u-dma-buf.c` files into the `petalinux/` directory. The only change needed was that I removed the `Makefile`'s lines for in-tree kernel variables and made sure the `obj-m` variable was properly handled (read up on kernel module Makefiles for more information on this).
```makefile
obj-m  += u-dma-buf.o
```
