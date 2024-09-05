# Snickerdoodle Linux Kernel

This is the source for the Snickerdoodle Black Linux kernel, based on the Xilinx Zynq Linux kernel. The kernel version is 5.4.0.

# Building Snickerdoodle kernel

Before anything, make sure you have the cross-compilation `gcc` tool for the ARM architecture (`arm-linux-gnueabihf-gcc`) on your `PATH`.

A good way to do this is to have the Xilinx toolchain installed. This was originally run with Vitis 2024.1. Run the `settings64.sh` script (you should probably source it in your `.bash_profile`) to set up the environment.

The full kernel build needs UBoot to be built first, but UBoot requires some scripts built from the kernel source.  So, the build process is a bit convoluted.


To first build the scripts of the kernel:
```bash
./build-kernel.sh -s
```

Next, to build UBoot:
```bash
./build-uboot -r
```

Finally, to build the kernel:
```bash
./build-kernel.sh -r
```
(This last one requires sudo permissions to properly build the filesystem).

To clean the directories, run:
```bash
./build-kernel.sh -c
./build-uboot -c
```
