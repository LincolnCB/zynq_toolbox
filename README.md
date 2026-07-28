***Updated 2026-07-20***

[![DOI](https://zenodo.org/badge/846674502.svg)](https://doi.org/10.5281/zenodo.20802348)

Forked off of and based originally on [Pavel Demin](https://github.com/pavel-demin)'s [Red Pitaya Notes](http://pavel-demin.github.io/red-pitaya-notes/).

Also heavily informed by and related to the Open-MRI [OCRA project](https://github.com/OpenMRI/ocra) (which was forked off of Pavel Demin's repo as well).

Primarily written by [Lincoln Craven-Brightman](https://scholar.google.com/citations?user=be3yqVEAAAAJ&hl=en&oi=ao), with contributions from Kutay Bulun, [Thomas Witzel](https://scholar.google.com/citations?hl=en&user=Pgc_3HwAAAAJ), and [H. Fatih Uǧurdag](https://scholar.google.com/citations?user=IdZE034AAAAJ&hl=en&oi=sra). The Revision D Shim firmware is designed to work with [Don Straney](https://dcstraney.wordpress.com/)'s [Linear Shim hardware (GitHub)](https://github.com/stockmann-lab/shim_amp_hardware_linear). The project is at the request and funding of [Jason Stockmann](https://scholar.google.com/citations?user=PxfOa-0AAAAJ&hl=en), and is a continuation of the work done by Nick Arango and [Irene Kuang](https://www.irenekuang.com/) on previous revisions of the Shim Amplifier system.

# Overview

This repository contains the source code and documentation for the Revision D Shim Amplifier system, as well as a general build framework if you're interested in modifying the system or building your own projects for a Zynq 7000 series SoC. These projects build the files for a bootable SD card that contain the Linux operating system, custom software, and FPGA bitstreams used in that project, which will fully configure your board.

The required AMD/Xilinx tools (PetaLinux + Vivado) can be set up two ways, covered side by side in this README. Either one will work.

- **In a VM** -- Original approach, a bulk package of the full build system. Everything, including the near-hundred-GB tool install (and the code in this repo!), lives inside one VM disk image.
- **In Docker** -- the tools live in an isolated Docker volume, separate from your host system and separate from the disposable container that runs them. Nothing installs directly onto your host, and rebuilding your dev environment doesn't mean reinstalling the toolchain.

## Sections

- [Overview](#overview)
- [Getting started](#getting-started)
- [Building an SD card](#building-an-sd-card)
- [Example projects](#example-projects)
- [Testing](#testing)

## Background -- Zynq 7000 series

Zynq 7000 SoCs are a series of System on Chip (SoC) devices from AMD/Xilinx that combine an ARM processor with an FPGA. There are several variants of the Zynq 7000 SoC series, including the Zynq 7010, Zynq 7020, and beyond. Different variants will have different I/O, memory, and processing capabilities, but they all share the same basic architecture, which allows most projects to be ported between them with minimal changes (unless you're at the limit of one of those resources and trying to port to a less-capable variant).

Zynq 7000 SoCs are available on a number of boards, including the Red Pitaya, the Snickerdoodle, Zybo boards, and many others. Different boards will have different Zynq variants -- for instance, the Red Pitaya STEMlab 125-14 uses the smaller Zynq 7010 chip, while the Snickerdoodle Black and Red Pitaya SDRlab 122-16 use the midrange Zynq 7020. In addition, different boards will expose different amounts of the Zynq's available I/O -- for instance, while the Snickerdoodle Black and Red Pitaya SDRlab 122-16 have the same Zynq 7020 chip, the Snickerdoodle Black has significantly more I/O pins accessible.

This repository is designed to allow compatibility with any board that uses a Zynq 7000 series chip, but may require some additional board files and configuration changes to work with a specific board. The full capabilities of the Rev D shim amplifier require the Zynq 7020 or above, as it uses the additional I/O and memory available on those chips. However, reducing the number of shim channels and buffer size would allow for porting.

## Repo structure

This repo is structured to allow for easy building of projects. It's primarily a collection of source code, configuration files, and scripts for the tools used -- Vivado and PetaLinux. There are some additional tools for testing, which you can read about in the [Testing](#testing) section.

The top-level directory contains the following folders (which each contain their own more in-depth README files):

- `boards`: Contains board files for boards that use the Zynq 7000 series SoCs. These files contain information about the board's hardware, like which Zynq variant is used or the I/O pinout. If you want to add support for a new board, you can take their board files (found online) and add a new folder here with the board's name containing the `board_files` folder.
- `documentation`: Contains images, markdown files, and other documentation external to the folder READMEs.
- `example_cores`: Contains example/custom cores used in the scripted build of the FPGA system, separated by "vendor" (original author). You can add your own custom cores here in your own folder, following the same structure as the others.
- `kernel_modules`: Contains kernel modules that can be included in the Linux kernel build for projects.
- `projects`: Contains the projects that can be built with this repo. Each project has its own folder, and is mainly defined by its `block_design.tcl` file, which defines the FPGA system's block design. Each project will also need folders under `cfg` that define compatibility with different boards, and can have a few other special folders that augment the build process.
- `scripts`: Contains scripts that are used to build projects, separated by category (`check`, `make`, `petalinux`, and `vivado`).

There are some temporary, untracked folders that contain the intermediate and final build results: `out` and `tmp`. In addition, there's a temporary `tmp_reports` folder that contains Vivado reports for resource utilization.

Finally, there's some files:

- `.gitmodules`: Declares this repo's git submodules. Make sure to clone with `--recurse-submodules` or run `git submodule update --init --recursive` afterward -- see [Cloning the repo](#cloning-the-repo).
- `environment.sh.example`: A template for environment variables, used by the **VM** installation path as explained in [Profile setup](#profile-setup). If you're following the **Docker** path, this file is generated for you automatically inside the container, and you generally won't need to touch it.
- `make_defaults.mk.example`: A template for makefile defaults (see [Makefile variable defaults](#makefile-variable-defaults)).
- `Makefile`: The main Makefile that is used to build everything, see [Building an SD card](#building-an-sd-card).

# Getting started

You should read through this section before starting any installation or cloning, to be sure you're setting up your environment as you intend.

Note that the recommended build environment is **LARGE** -- you're looking at needing 200 GB of disk space to store all the tools and your output files. You can get away with a bit less than this by using the online PetaLinux caches instead of pre-downloading them, but you should make sure your system can handle the size of this build pipeline!

## Required tools

This repo uses the AMD/Xilinx FPGA toolchain to build projects for the chips in the Zynq 7000 SoC series family. These tools are fairly large and have particular requirements. As a result, you will have the best results installing them in a controlled Linux environment. The recommended options for this are to either install in a Virtual Machine (VM) or using Docker containers. 

Both of these options are supported, and each have their benefits. VM's are more monolithic, but may require more fiddling to connect your USB peripherals and will definitely cause a performance hit. Using Docker containers is a bit more engaged of a setup process, but allows this build repo to live directly on your host computer (easier to adjust and handle build results) and dynamically utilize much more of your system's resources.

> Please read the [VM install instructions](documentation/vm_install.md) or the [Docker install instructions](documentation/docker_install.md) for your chosen path. The rest of this README is basically the same for both paths (but make sure to indicate which one you chose in your [Makefile variable defaults](#makefile-variable-defaults)).

## Makefile variable defaults

The Makefile is set up to use the variables `PROJECT`, `BOARD`, and `BOARD_VER` to determine which project, board, and board version to build, as well as a couple others (see [Building an SD card](#building-an-sd-card), [Building a different board, board version, or project](#building-a-different-board-board-version-or-project), [Building PetaLinux offline](#building-petalinux-offline), and [Script targets](#script-targets) for more information). To set personal default values for these variables, copy

```
make_defaults.mk.example
```

into the file

```
make_defaults.mk
```

and make your edits there, inside your repo checkout.

**Make sure to set your `MODE` to either `container` or `vm` depending on whether you installed in a Docker or VM configuration**. You can set the other variables to whatever you'd like as your defaults.

Just like `environment.sh`, only the example file is tracked, so you can edit `make_defaults.mk` without worrying about it being overwritten by a `git pull` or similar command.

# Building an SD card

This section will walk you through the build process of a fully formed bootable Micro SD card for the Snickerdoodle Black containing the Rev D Shim firmware, Linux operating system, and FPGA bitstream. If you want to understand the steps in more detail, go through the [Example projects](#example-projects) section, which progressively build up the components and techniques used for the Rev D Shim firmware.

The entire build process is scripted by the `Makefile` and various shell and Tcl scripts in the `scripts/` directory. The main entry point is the `Makefile`, which will call the appropriate scripts to build the project. The default target and variables for the `Makefile` are the Rev D Shim firmware for the Snickerdoodle Black. From your VM shell or inside the dev container (whichever path you took), run the following from the root of this repository:

```
make
```

This will output two compressed files in the `out/snickerdoodle_black/1.0/zynq_toolbox/` directory:

- `BOOT.tar.gz`: The compressed boot partition, which contains the Linux kernel, device tree, and boot scripts.
- `rootfs.tar.gz`: The compressed root filesystem, which contains all of the Linux files.

(Docker path: since the repo is bind-mounted rather than copied into the container, these files appear directly on your host, no copying required.)

To load these files onto the Micro SD card, you'll first need one with the proper partitioning scheme. This follows the instructions given in the [PetaLinux Tools Documentation (UG1144)](https://docs.amd.com/r/en-US/ug1144-petalinux-tools-reference-guide/Preparing-the-SD-Card). You can use any disk partitioning tool to do this, but Linux ones are generally better/easier to use.

- **VM path:** writing to the SD card is easiest if your VM has access to your SD card reader / USB port, so it's recommended to do the partitioning through your VM as well -- GParted is a good graphical tool for this, which you can install with `sudo apt install gparted` if it isn't already.
- **Docker path:** do this part on your host, not inside the container -- the container has no access to your SD card reader by default, and there's no need to grant it USB/block-device access just to run a partitioning tool. Use whichever tool you're comfortable with on your host OS (GParted on Linux, Disk Utility on macOS, Rufus/Disk Management on Windows, etc.).

Either way, partition the SD card as follows:

- One partition of type `fat32` with a size of 1 GiB, labeled `BOOT`. Make sure this has 4 MiB of unallocated free space before it.
- One partition of type `ext4` with a size of whatever is left on the SD card, labeled `RootFS`.

Once the SD card is partitioned, you can uncompress the `BOOT.tar.gz` and `rootfs.tar.gz` files into the respective partitions. If you're on Linux (VM or Docker host) and using the default `BOARD`, `BOARD_VER`, and `PROJECT` (`snickerdoodle_black`, `1.0`, `zynq_toolbox`), you can do this with the following [target](#script-targets) (may need to eject and re-insert the SD card after partitioning) -- run this from wherever you did the partitioning (your VM shell for the VM path, your host shell for the Docker path, not inside the container):

```
make write_sd
```

which will attempt to find the SD card partitions automatically at `/media/username/BOOT` and `/media/username/RootFS`, where `username` is your username on the system. If the partitions are mounted somewhere else, you can specify the mount folder as an additional argument:

```
make write_sd MOUNT_DIR=[mountpoint]
```

where `[mountpoint]` is the folder containing the mounted `BOOT` and `RootFS` directories. As with any `make` targets, you can modify the `BOARD`, `BOARD_VER`, and `PROJECT` variables to build for a different board, board version, or project (see the [Building a different board, board version, or project](#building-a-different-board-board-version-or-project) section below).

You can similarly clean the SD card files from the mounted SD card with:

```
make clean_sd
```

again with an optional `MOUNT_DIR` argument to specify the mount point of the SD card partitions.

If you have some other mounting scheme (or you're on macOS/Windows), you'll need to manually uncompress the files into the appropriate partitions with `tar`:

```
tar -xzf out/snickerdoodle_black/1.0/BOOT.tar.gz -C [BOOT_mountpoint]
tar -xzf out/snickerdoodle_black/1.0/rootfs.tar.gz -C [RootFS_mountpoint]
```

If your board isn't the Snickerdoodle Black, or you want to modify the project or build your own, you should read the [Example projects](#example-projects) section to get a sense of how everything works.

## Building a different board, board version, or project

The Makefile is set up to read variables for `BOARD`, `BOARD_VER`, and `PROJECT` from the command line. These can be used to build with a different board, board version, or project. For example, to build the `shim_controller_v0` project for version `1.0` of the Red Pitaya `sdrlab_122_16` board, you can run:

```
make BOARD=sdrlab_122_16 BOARD_VER=1.0 PROJECT=shim_controller_v0
```

Boards and board versions are defined in the `boards/` directory, where the board files for a given board are given under `boards/[BOARD]/board_files/[BOARD_VER]/`. Projects are defined based on folders in the `projects/` directory, where each project has its own folder. Note that projects need to be configured to work with a specific board and board version -- this is done under `projects/[PROJECT]/cfg/[BOARD]/[BOARD_VER]/`, and requires configuration files for `petalinux` and the Vivado Xilinx Design Constraint `xdc` files. You can read more about the requirements for this configuration in the `projects/` directory's README file.

## Building PetaLinux offline

If you set up the PetaLinux offline cache in either [your VM](./documentation/vm_install.md#optional-recommended-petalinux-offline-build-setup), you can include the `OFFLINE=true` variable in the `make` command to use the local files instead of downloading them. For example, to build the Rev D Shim firmware for the Snickerdoodle Black with offline PetaLinux, you can run:

```
make OFFLINE=true
```

You can also set this as a default in your [Makefile variable defaults](#makefile-variable-defaults).

## Intermediate build files and targets

The Makefile is set up to build the project in a series of steps, with intermediate files stored in the `tmp/` directory. These targets can also be made individually, if you want to debug the build or explore the intermediate files. There are also some targets for cleaning or running tests. `Makefile` has a lot of comments, so feel free to check that out as well. The main targets are:

### Default target

- `all`: The default target, which will be run if no target is provided. This will build `sd` and `tests`.

### Script targets

- `tests`: Run tests for all cores in the project. Test summaries per core will be placed in `example_cores/[vendor]/cores/[core]/tests/test_status`, and a summary of all core tests for the project will be placed in `projects/[project]/tests/core_tests_summary`.
- `write_sd`: Write the SD card files to the SD card. The default mount point is `/media/[username]/`, but can be overridden with the `MOUNT_DIR` variable. This will write the `BOOT.tar.gz` and `rootfs.tar.gz` files to the appropriate partitions on the SD card, as described in the [Building an SD card](#building-an-sd-card) section. (Docker path: run this on your host, not inside the container.) Uses the `scripts/make/write_sd.sh` script.
- `petalinux_cfg`: Generate or update the PetaLinux system configuration files for the project, under `projects/[project]/cfg/[board]/[board_ver]/petalinux/[petalinux_ver]/`. Uses the `scripts/petalinux/petalinux_cfg.sh` script. Requires the terminal to be above a certain size to display the PetaLinux config GUI.
- `petalinux_rootfs_cfg`: Generate or update the PetaLinux root filesystem configuration files for the project, under `projects/[project]/cfg/[board]/[board_ver]/petalinux/[petalinux_ver]/`. Uses the `scripts/petalinux/petalinux_rootfs_cfg.sh` script. Requires the terminal to be above a certain size to display the PetaLinux config GUI.
- `clean_sd`: Clean the SD card files from a mounted SD card. The default mount point is `/media/[username]/`, but can be overridden with the `MOUNT_DIR` variable. Uses the `scripts/make/clean_sd.sh` script.
- `clean_project`: Remove a single project's intermediate and temporary files, including Vivado-packaged cores from `tmp/`.
- `clean_build`: Remove all the intermediate and temporary files, including Vivado-packaged cores from `tmp/`, as well as reports in `tmp_reports`.
- `clean_tests`: Remove the `results` directory from all core test folders (under `example_cores/[vendor]/cores/[core]/tests/`), but leave the `test_status` file.
- `clean_test_results`: Remove the `test_status` file from all core test folders, as well as the `core_tests_summary` file from all project test folders (under `projects/[project]/tests/`). Runs `clean_tests` first.
- `clean_all`: Run all the clean targets above and additionally remove any output files in `out/`.

### Main build targets

- `sd`: Build the full SD card files for the project (`rootfs` and `boot`), which will be placed in `out/[board]/[board_ver]/[project]/`.
- `bit`: Build a standalone bitstream for the project, which will be placed in `out/[board]/[board_ver]/[project]/`. This can be used if you're using a different workflow than PetaLinux and just want the bitstream file to load the FPGA configuration.
- `rootfs`: Build the root filesystem half of the `sd` files.
- `boot`: Build the boot partition half of the `sd` files.

### Intermediate build targets

- `cores`: Build all the Vivado-packaged custom cores for the project, which will be placed in `tmp/cores/[vendor]/[core]/`. This is the first step of the overall `sd` target.
- `xpr`: Build the Vivado project file for the project, which will be placed at `tmp/[board]/[board_ver]/[project]/project.xpr`. This step requires `cores` and is part of the overall `sd` target.
- `xsa`: Build the Vivado Xilinx hardware definition `XSA` file for the project, which will be placed at `tmp/[board]/[board_ver]/[project]/hw_def.xsa`. This step requires `xpr` and is part of the overall `sd` target.
- `petalinux`: Build the PetaLinux project for the project, which will be the folder `tmp/[board]/[board_ver]/[project]/petalinux/`. This step requires `xsa` and is part of the overall `sd` target.

There are other specific targets in the Makefile, but they aren't recommended for direct use unless you know what you're doing.

## Using the Rev D Shim Amplifier

Once you've built the Rev D Shim firmware, please refer to the README in the `projects/rev_d_shim/` directory for instructions on how to use it.

# Example projects

To understand the build processes in this repo, it's recommended to explore the example projects in the `projects/` directory, as well as the README in the `projects/` directory itself. As a quick summary, each project has its own folder, and the example projects are prefixed with `ex##_`, where `##` is the example number. They're ordered to progressively build up the scripting and configuration concepts needed to build the Rev D Shim firmware, so they should be a good starting point for understanding how to build your own projects.

You should read through the README in each of their respective folders, but in brief, the example projects are:

## EX01 -- Basics

This example project is mostly a template for the minimum viable project. It will walk you through the basic steps that any project will use, explaining the fundamental Vivado and PetaLinux build steps, including how to incorporate basic software or files in the built SD card. This is necessary to build the Rev D Shim PS and PL components.

## EX02 -- AXI interface

This example project explores more of the Vivado Tcl scripting capabilities and demonstrates the basic AXI interface, which will be how the Zynq's CPU / processing system (PS) communicates with the FPGA / programmable logic (PL). It includes some playground software to try out various AXI interfaces. This is necessary for the Rev D Shim firmware to actually control the hardware, as it needs to communicate with the FPGA to set the shim channels and read the buffer data (among other things).

## EX03 -- UART

This example project demonstrates some configuration options for the PS's interfaces, including its UART interface. It's a good overview of how to connect the Zynq's PS to an external computer via a UART interface. This is necessary for the Rev D Shim firmware to communicate with an external host computer outside of the scanner room.

## EX04 -- Interrupts

This example project covers interrupts from the PL to the PS and software to handle that, allowing the PL to signal the PS when it needs attention. This is necessary for the safety features of the Rev D Shim firmware.

# Testing

Testing is done using [cocotb](https://www.cocotb.org/), a Python-based testbench framework for digital design verification. It allows you to write tests in Python and run them in a simulator, such as Verilator. To install the tools needed for testing, see [Optional: Running tests](#optional-running-tests) above (covers both the VM and Docker paths).

To run tests for a specific core, you can use the `test_core.sh` script in the `scripts/make/` directory with the `vendor` and `core` arguments. For example, to test the `fifo_sync` core from `base`, you can run:

```
./scripts/make/test_core.sh base fifo_sync
```

This will run the tests for the `fifo_sync` core under `example_cores/base/cores/fifo_sync/tests/src` and output a test status report at `example_cores/base/cores/fifo_sync/tests/test_status`.

To run tests for all cores in a project, you can use the make target `tests`. For example, to run tests for the `rev_d_shim` project, you can run:

```
make tests PROJECT=rev_d_shim
```
