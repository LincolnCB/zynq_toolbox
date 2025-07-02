***Updated 2025-07-01***
# Kernel modules

This directory contains source code for custom kernel modules that can be added to the Linux kernel built from PetaLinux. These are used with the `scripts/petalinux/kernel_modules.sh` script and can be added to projects by adding the module name to the file 
```
projects/[project_name]/cfg/[board_name]/[board_version]/petalinux/kernel_modules
```

These modules will be built "out-of-tree" and included in the PetaLinux build, but still need to be enabled with `modprobe` or `insmod` after the board is booted.

## Kernel module directory structure

Each directory in this directory is its own kernel module. The name of the directory is the name of the kernel module. Each module directory can contain extra files for clarity (`README.md` or any general documentation or source files), but primarily contains a `petalinux/[petalinux_version]/` directory for each supported version of PetaLinux. 

Within these directories, the source code is composed of a kernel `Makefile`, a top-level `.c` C file, and any other `.c` files needed for the module. These files should work the same as any type of kernel source code -- for instance, getting the `u-dma-buf` kernel module from its [GitHub repo]([https://github.com/ikwzm/udmabuf/tree/master]), I directly copied the `Makefile` and `u-dma-buf.c` files into the `petalinux/2024.2/` directory. The only change needed was that I removed the `Makefile`'s lines for in-tree kernel variables and made sure the `obj-m` variable was properly handled (read up on kernel module Makefiles for more information on this).
```makefile
obj-m  += u-dma-buf.o
```

From there, the `ex05_dma` project properly builds and loads the module with the `projects/ex05_dma/cfg/snickerdoodle_black/1.0/petalinux/kernel_modules` file containing the line:
```
u-dma-buf
```
