Based on Pavel Demin's Notes on the Red Pitaya Open Source Instrument
[http://pavel-demin.github.io/red-pitaya-notes/]
as well as the Open-MRI OCRA project (also based off of Pavel Demin's repo)
[https://github.com/OpenMRI/ocra]


# Rev D Shim

## Getting Started

### Required Tools

To build the system, you'll need the following tools. The versions listed are the ones that have been tested and are known to work. Other versions may work, but are not guaranteed to. I recommend using a VM for this, as the installation can be large and messy. For the recommended versions listed below, I used a Ubuntu 22.04.4 VM with 160 GB of storage, 16 GB of RAM, and 8 CPU cores. My process is explained below, but is definitely not the only way to do this.

- PetaLinux (2024.1)
- Vivado (2024.1)

These can be installed together from the AMD unified installer (2024.1 version [here](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-design-tools/2024-1.html)).


### Installing PetaLinux

Follow the documentation [here](https://docs.amd.com/r/2024.1-English/ug1144-petalinux-tools-reference-guide/Installation-Steps). 

For my system, I had to first make sure the VM had the required libraries. From the stock Ubuntu install, I installed the following packages:
```
libtools texinfo ncurses-term libtinfo5 libncurses5 python3-pip libgtk2.0-0 gawk gcc netstat libncurses5-dev openssl xterm zlib1g-dev gcc-multilib build-essential automake screen libstdc++6 g++ xz-utils cpp patch python3-jinja2 python3-pexpect diffutils debianutils iputils-ping python3 cpio gnupg
```

After that, installation went smoothly. Installation was a 4 GB download, 8 GB required disk space, and 4 GB final install size. I selected only PetaLinux ARM, as that's what has the Zynq 7000 series Cortex A9 support.

Note that PetaLinux requires bash to be your shell.


### Installing Vivado

I installed Vivado using the Vitis installation process, and installed Vitis as well. I don't believe you need Vitis, currently. I used the default options for Vitis and Vivado, and only selected the Zynq 7000 series and Artix-7 FPGA. The installation was a 20 GB download, 100 GB required disk space, and 50 GB final install size.

Relative to the Xilinx installation directory, I ran `Xilinx/Vitis/2024.1/scripts/installLibs.sh` with sudo.


## Profile Setup

Your shell needs to have environment variables set up for the tools to work. The following three are needed:
- `PETALINUX_PATH`: The path to the PetaLinux installation directory (e.g. `/tools/Xilinx/PetaLinux/2024.1/tool`)
- `VIVADO_PATH`: The path to the Vivado installation directory (e.g. `/tools/Xilinx/Vivado/2024.1`)
- `REV_D_DIR`: The path to the root of this repository

You also need to modify the Vivado init script, which runs each time Vivado does. In particular, you need to source this repo's initialization script. Read the information inside `scripts/vivado/repo_paths.tcl` for more information.


## Building a project

To make a project, you can run
```
make PROJECT=<project_name> BOARD=<board_name>
```

The default make target is `sd`

The Makefile utilizes shell and TCL (Vivado's preferred scripting language) scripts to build the project.

The Makefile will (with the help of the scripts, and marked by which build target delineates what):
- Check the the project and board directories exist and contain most of the necessary files (no promises that it'll catch everything, but I tried to make it verbose).
- Parse the project's `block_design.tcl` file to find the cores (using `get_cores_from_tcl.sh`) used in the project. This is done in order to save time. You can manually build all cores with `make cores`.
- `make xpr`: Run the script `scripts/vivado/project.tcl` to Build the Vivado project `project.xpr` file in the `tmp/[board]/[project]/` directory, using the following files in `projects/[project]`:
  - `ports.tcl`, the TCL definition of the block design ports
  - `block_design.tcl`, the TCL script that constructs the programmable logic. Note that `scripts/vivado/project.tcl` defines useful functions that `block_design.tcl` can utilize, please check those out.
  - The Xilinx design constraint `.xdc` files in `cfg/[board]/xdc/`. These define the hardware interface. 
- `make xsa`: Run the script `scripts/vivado/hw_def.tcl` to generate the hardware definition file `hw_def.xsa` in the `tmp/[board]/[project]/` directory.
- `make sd`: Run the scripts `petalinux_build.sh` to build the PetaLinux-loaded SD card files for the project. This will output the final files to `out/[board]/[project]/`. It will create a compressed file for each of the two partitions listed in the [PetaLinux SD card partitioning documentation](https://docs.amd.com/r/2024.1-English/ug1144-petalinux-tools-reference-guide/Preparing-the-SD-Card). This requires the `PETALINUX_PATH` environment variable to be set, and PetaLinux project and rootfs config files (stored as differences from the default configurations) in the `projects/[project]/petalinux_cfg/` directory.
  - To create new PetaLinux configuration files in the correct format for this script, you can use the scripts `petalinux_config_project.sh` and `petalinux_config_rootfs.sh` in the `scripts/` directory. These scripts will create the necessary files in the `projects/[project]/petalinux_cfg/` directory.

## Common build failures

- Running out of disk space: Run `make clean` to remove the `tmp/` directory. This directory is used to store the Vivado project files, and can get quite large.
- Network issues with PetaLinux: If your network connection is messy, PetaLinux can grind to a hald in the bitbake process. I'm not sure the best way to avoid this, aside from improving your connection.

## Adding a board

See the README in the `boards/` directory.

## Adding a core

See the README in the `cores/` directory.

## Adding a project

See the README in the `projects/` directory.

## Configuring PetaLinux for a project

See the README in the `projects/` directory.


## Directory Structure

This repository is organized as follows. Repositories will contain README files with more information on the folders and files within them (when I get to it...).
```
rev_d_shim/
├── boards/                               - Board files for different supported boards
├── cores/                                - Custom IP cores for use in Vivado's block design build flow
├── modules/                              - Custom modules used in other cores
├── projects/                             - Files/scripts to build particular projects
├── scripts/                              - Scripts used in building projects
├── README.md                             - This file
```
