Forked off of and based originally on Pavel Demin's Notes on the Red Pitaya Open Source Instrument
[http://pavel-demin.github.io/red-pitaya-notes/]

Also heavily informed by the Open-MRI OCRA project (which was forked off of Pavel Demin's repo as well)
[https://github.com/OpenMRI/ocra]


# Getting Started

## Required Tools

This repo uses the AMD/Xilinx FPGA toolchain to build projects for the chips in the Zynq 7000 SoC series family. Below are some instructions on how to set up the tools. The versions listed are the ones that are primarily used, but other versions may work as well. If you use other versions of tools, you may need to add configuration files for them to projects (PetaLinux, in particular, changes its configuration files meaningfully between versions) -- this will be explained later in the section on configuring PetaLinux for a project.

I recommend using a VM for these tools, as the installation can be large and messy, and the tools' supported OSes are slightly limited. For the recommended versions listed below, I used a VM running [Ubuntu 20.04.6 (Desktop image)](https://www.releases.ubuntu.com/focal/) with 200 GB of storage(/disk space), 16 GB of RAM(/memory), and 8 CPU cores. If you're running on a Mac with a M1/M2 or other non-x86 chip, you may need to be picky with your VM to do this ([UTM](https://mac.getutm.app/) seems to be the recommended option. Make sure to select "iso image" when selecting the downloaded Ubuntu ISO). My process is explained below, but is definitely not the only way to do this.

- PetaLinux (2024.2)
- Vivado (2024.2)

These can be installed together from the AMD unified installer (2024.2 version [here](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-design-tools/2024-2.html) -- select "AMD Unified Installer for FPGAs & Adaptive SoCs 2024.2: Linux Self Extracting Web Installer", do this and everything else on the system you want these tools installed to, which is recommended to be a VM). You will need to create an AMD account to download and use the installer, but it should be free to do so. 


### Unified Installer

Follow the documentation [here](https://docs.amd.com/r/en-US/ug1144-petalinux-tools-reference-guide/Installation-Steps) -- make sure the dropdown version at the top of the documentation matches the version you're using. 

You should make sure the system had the required libraries. From the stock Ubuntu 20.04.6 install, I needed to install the following packages with `sudo apt install` to make PetaLinux and Vivado install successfully:
```shell
sudo apt install gcc xterm autoconf libtool texinfo zlib1g-dev gcc-multilib build-essential libncurses5-dev libtinfo5
```

To run the unified installer, you will likely need to make it executable first. This is done by running (from the folder containing the installer, which will likely be your Downloads folder):
```shell
chmod +x FPGAs_AdaptiveSoCs_Unified_2024.2_1113_1001_Lin64.bin
```

From there, you can run the installer (this will need `sudo` permissions to write to the recommended default installation directory, which is `/tools/Xilinx/`).
```shell
sudo ./FPGAs_AdaptiveSoCs_Unified_2024.2_1113_1001_Lin64.bin
```

This will open a GUI installer. You will need to log in with your AMD account again. This will take you to the "**Select Product to Install**" page. You will need to run this installer twice, once for each of the two tools (PetaLinux and Vivado). I recommend starting with PetaLinux, as it is smaller and quicker to install.

### Installing PetaLinux

On the "**Select Product to Install**" page, scroll to the bottom and select "**PetaLinux**" and click Next. This repo is primarily focused on the Zynq7000 series SoCs, so you can select "**PetaLinux arm**" under "**Select Edition to Install**" and click Next. Accept the License Agreements and click Next. You can leave everything as default under "**Select Destination Directory**" (the default will be `/tools/Xilinx/` and will create a `PetaLinux/2024.2` directory). Click Next and then Install.


### Installing Vivado

Running the unified installer again, back on the "**Select Product to Install**" page, "**Vivado**" should be the second option. Select it and click Next. Under "**Select Edition to Install**", select "**Vivado ML Standard**" and click Next. The next section, "**Vivado ML Standard**", allows you to trim the installation size to only the components needed. First, I recommend unchecking everything you can. You can then check the following options:
- **DocNav** (optional) for looking at documentation in the Vivado GUI. Documentation can also be found online.
- Under **Devices** -> **Production Devices** -> **SoCs** check **Zynq-7000**  (you may need to expand the sections to see this. It's fine that it says "limited support").

Click Next. Accept the Licence Agreements and click Next. Just like with PetaLinux, you can leave everything as default under "**Select Destination Directory**" (the default will be `/tools/Xilinx/` and will create a `Vivado/2024.2` directory). Click Next and then Install.


## Profile Setup

With this repository cloned into your VM (e.g. `/home/username/rev_d_shim` or something similar), you will need to set up some environment variables and modify the Vivado init script to use this repo's scripts. At the top level of this repository, you will find a file named `environment.sh.example`. This is a template file for the environment variables that you need to set up. Copy this file and name the copy `environment.sh`. You will need to edit the following variables in this file to match your setup:
- `REV_D_DIR`: The path to the repository root directory (e.g. `/home/username/rev_d_shim`, as above)
- `PETALINUX_PATH`: The path to the PetaLinux installation directory (by default, this will be `/tools/Xilinx/PetaLinux/2024.2/tool`)
- `PETALINUX_VERSION`: The version of PetaLinux you are using (e.g. `2024.2`)
- `VIVADO_PATH`: The path to the Vivado installation directory (by default, this will be `/tools/Xilinx/Vivado/2024.2`)


---
# WORK IN PROGRESS BELOW THIS POINT

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
└── README.md                             - This file
```
