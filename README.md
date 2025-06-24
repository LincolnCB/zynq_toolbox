Forked off of and based originally on Pavel Demin's Notes on the Red Pitaya Open Source Instrument
[http://pavel-demin.github.io/red-pitaya-notes/]

Also heavily informed by the Open-MRI OCRA project (which was forked off of Pavel Demin's repo as well)
[https://github.com/OpenMRI/ocra]

Primarily written by Lincoln Craven-Brightman, with contributions from Kutay Bulun, Thomas Witzel, and H. Fatih Uǧurdag. The Revision D Shim firmware is designed to work with Don Straney's [Linear Shim hardware (GitHub)](https://github.com/stockmann-lab/shim_amp_hardware_linear). The project is at the request and funding of Jason Stockmann, and is a continuation of the work done by Nick Arango and Irene Kuang on previous revisions of the Shim Amplifier system.

# Overview

This repository contains the source code and documentation for the Revision D Shim Amplifier system, as well as a general build framework if you're interested in modifying the system or building your own projects for a Zynq 7000 series SoC. These projects build the files for a bootable SD card that contain the Linux operating system, custom software, and FPGA bitstreams used in that project, which will fully configure your board.

## Sections

- [Overview](#overview)
- [Getting Started](#getting-started)
- [Building an SD card](#building-an-sd-card)
- [Example Projects](#example-projects)
- [Testing](#testing)

## Background -- Zynq 7000 Series

Zynq 7000 SoCs are a series of System on Chip (SoC) devices from AMD/Xilinx that combine an ARM processor with an FPGA. There are  several variants of the Zynq 7000 SoC series, including the Zynq 7010, Zynq 7020, and beyond. Different variants will have different I/O, memory, and processing capabilities, but they all share the same basic architecture, which allows most projects to be ported between them with minimal changes (unless you're at the limit of one of those resources and trying to port to a less-capable variant).

Zynq 7000 SoCs are available on a number of boards, including the Red Pitaya, the Snickerdoodle, Zybo boards, and many others. Different boards will have different Zynq variants -- for instance, the Red Pitaya STEMlab 125-14 uses the smaller Zynq 7010 chip, while the Snickerdoodle Black and Red Pitaya SDRlab 122-16 use the midrange Zynq 7020. In addition, different boards will expose different amounts of the Zynq's available I/O -- for instance, while the Snickerdoodle Black and Red Pitaya SDRlab 122-16 have the same Zynq 7020 chip, the Snickerdoodle Black has significantly more I/O pins accessible. 

This repository is designed to allow compatibility with any board that uses a Zynq 7000 series chip, but may require some addition board files and configuration changes to work with a specific board. The full capabilities of the Rev D shim amplifier require the Zynq 7020 or above, as it uses the additional I/O and memory available on those chips. However, reducing the number of shim channels and buffer size would allow for porting.

## Repo structure

This repo is structured to allow for easy building of projects. It's primarily a collection of source code, configuration files, and scripts for the tools used -- Vivado and PetaLinux. There are some additional tools for testing, which you can read about in the  [Testing](#testing) section.

The top-level directory contains the following folders (which each contain their own more in-depth README.md files):
- `boards`: Contains board files for boards that use the Zynq 7000 series SoCs. These files contain information about the board's hardware, like which Zynq variant is used or the I/O pinout. If you want to add support for a new board, you can take their board files (found online) and add a new folder here with the board's name containing the `board_files` folder.
- `custom_cores`: Contains custom cores used in the scripted build of the FPGA system. These cores are separated by "vendor", basically meaning the original author. For instance, the `pavel_demin` folder contains cores that were originally written by Pavel Demin, while the `open_mri` folder contains cores that were originally written by people in the Open-MRI OCRA project (likely Thomas Witzel). Cores in `lcb` were primarily written by me, Lincoln Craven-Brightman, with contributions from folks like Kutay Bulun, H. Fatih Uǧurdag, and Thomas Witzel. You can add your own custom cores here in your own folder, following the same structure as the others.
- `kernel_modules`: Contains kernel modules that can be included in the Linux kernel build for projects.
- `projects`: Contains the projects that can be built with this repo. Each project has its own folder, and is mainly defined by its `block_design.tcl` file, which defines the FPGA system's block design. Each project will also need folders under `cfg` that define the compatibility with different boards, and can have a few other special folders that augment the build process.
- `scripts`: Contains scripts that are used to build projects, separated by category (`check`, `make`, `petalinux`, and `vivado`).

There are some temporary, untracked folders that contain the intermediate and final build results: `out` and `tmp`. In addition, there's a temporary `tmp_reports` folder that contains Vivado reports for resource utilization.

Finally, there's some files:
- `environment.sh.example`: Needs to be copied as explained in [Profile Setup](#profile-setup) 
- `Makefile`: The main Makefile that is used to build everything.


# Getting Started

## Required Tools

This repo uses the AMD/Xilinx FPGA toolchain to build projects for the chips in the Zynq 7000 SoC series family. Below are some instructions on how to set up the tools. The versions listed are the ones that are primarily used, but other versions may work as well. If you use other versions of tools, you may need to add configuration files for them to projects (PetaLinux, in particular, changes its configuration files meaningfully between versions) -- this will be explained later in the section on configuring PetaLinux for a project.

I recommend using a VM for these tools, as the installation can be large and messy, and the tools' supported OSes are slightly limited. For the recommended versions listed below, I used a VM running [Ubuntu 20.04.6 (Desktop image)](https://www.releases.ubuntu.com/focal/) with 200 GB of storage(/disk space), 16 GB of RAM(/memory), and 8 CPU cores. If you're running on a Mac with a M1/M2 or other non-x86 chip, you may need to be picky with your VM to do this ([UTM](https://mac.getutm.app/) seems to be the recommended option. Make sure to select "iso image" when selecting the downloaded Ubuntu ISO). In terms of installing Ubuntu on the VM, I recommend a "Minimal Install" and not to "Download Updates" to keep it as simple and close to the original, supported edition as possible. 

My process is explained below, but is definitely not the only way to do this.

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

## Changing your default shell to Bash

PetaLinux requires the default shell to be Bash. In Ubuntu 20.04.6 (and most other Ubuntu versions), the default shell is Dash. The default shell is the `/bin/sh` file, which is a symlink to the binary of another shell. You can check your current default shell by running:
```shell
ls -l /bin/sh
```
This will output something like:
```
lrwxrwxrwx 1 root root 4 Mar 31  2024 /bin/sh -> dash
```
This means that the default shell is currently Dash. 

To change it to Bash, you can run:
```shell
sudo ln -sf /bin/bash /bin/sh
```
which overrides the symlink to point to Bash instead of Dash. 

Checking again with `ls -l /bin/sh` should now output:
```
lrwxrwxrwx 1 root root 9 Apr 29 01:13 /bin/sh -> /bin/bash
```

## Profile Setup

With this repository cloned into your VM (e.g. `/home/username/rev_d_shim` or something similar), you will need to set up some environment variables and modify the Vivado init script to use this repo's scripts. At the top level of this repository, you will find a file named `environment.sh.example`. This is a template file for the environment variables that you need to set up. Copy this file and name the copy `environment.sh`. You will need to edit the following variables in this file to match your setup:
- `REV_D_DIR`: The path to the repository root directory (e.g. `/home/username/rev_d_shim`, as above)
- `PETALINUX_PATH`: The path to the PetaLinux installation directory (by default, this will be `/tools/Xilinx/PetaLinux/2024.2/tool`)
- `PETALINUX_VERSION`: The version of PetaLinux you are using (e.g. `2024.2`)
- `VIVADO_PATH`: The path to the Vivado installation directory (by default, this will be `/tools/Xilinx/Vivado/2024.2`)

The remaining lines are optional or do not need to be changed:
- `source $VIVADO_PATH/settings64.sh`: This line sources a Vivado script that sets up the terminal environment for Vivado. This should be left as is.
- `PETALINUX_DOWNLOADS_PATH`/`PETALINUX_SSTATE_PATH`: These are optional variables only needed if you want to do offline builds with PetaLinux. See the **Building PetaLinux Offline** section below for more information.

With `environment.sh` set up, you will need to source it in your shell. Add the following line to one of the files that is sourced in new Bash terminals, where \[path_to_rev_d_shim\] is the path to the root of this repository (e.g. `/home/username/rev_d_shim`):
```bash
source [path_to_rev_d_shim]/environment.sh
```

### Which Bash file to add the source line to?

Feel free to skip this section if you already know how to set up your Bash profile files.

Bash has a number of profile files: `~/.bashrc`, `~/.bash_profile`, and `~/.profile` are common, as well as the lesser-used `/etc/profile` and `~/.bash_login`. Here's a short summary of [what each of those files does](https://www.baeldung.com/linux/bashrc-vs-bash-profile-vs-profile).

My preferred way is to only have `~/.profile` and `~/.bashrc`. Here's how that works:

When logging in with a terminal, you're opening an *interactive, login* shell. In this case, Bash will try to source the first of whichever is present, in order: `~/.bash_profile`, then `~/.bash_login`, then `~/.profile`. `~/.profile` is also used by some other shells like Dash.

When opening a new terminal window, you're opening an *interactive, non-login* shell. In this case, Bash will source `~/.bash_rc`.

`~/.profile` may contain lines sourcing `~/.bashrc`, which I would like to make sure only runs in interactive shells. To do this, I just replace any line that does so:
```bash
. "$HOME/.bashrc"
```
with:
```bash
if [[ $- == *i* ]]; then . "$HOME/.bashrc"; fi
```
which checks if the `$-` variable (containing single letter flags about the terminal status) contains `i` (interactive).

All of this gives me the following  `~/.profile`, in its entirety:

```bash ~/.profile
# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
	if [[ $- == *i* ]]; then . "$HOME/.bashrc"; fi
    fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi

# Source the Rev D environment script
source $HOME/rev_d_shim/environment.sh
```

However, `~/.profile` is only sourced if `~/.bash_profile` and `~/.bash_login` don't exist. If `~/.bash_profile` already exists, you can delete it. If it needs to exist, just source `~/.profile` in it.

```bash
#~/.bash_profile
# Just source .profile
. "$HOME/.profile"
```
You can do similarly with `~/.bash_login` if it exists, but I've never really seen it used.

## Optional: Building PetaLinux Offline

The PetaLinux build process requires downloading a lot of files from the internet, which can be slow and unreliable. Depending on your network connection, this could add upwards of ten minutes to the build time. If you want to put in a bit of effort for a more reliable build process, you can download these files and store them locally, so that PetaLinux can use them without needing to download them each time.

For PetaLinux 2024.2, you can download the files from the [AMD download center](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/embedded-design-tools/2024-2.html). The files you will need are all the way at the bottom, under **PetaLinux Tools sstate-cache Artifacts** (you can ignore the final section, Update 1). You'll need to download two files:
- `arm sstate-cache` (TAR/GZIP - ~9 GB) 
- `Downloads` (TAR/GZIP - ~59 GB)

You'll want to extract these files to some directory on your system. From there, you can set the `PETALINUX_DOWNLOADS_PATH` and `PETALINUX_SSTATE_PATH` environment variables in your `environment.sh` file to point to the directories where you extracted these files. Each archive has a simply named directory at the top, `downloads` and `arm`. For example, if you have the following directory structure:
```
~/petalinux_downloads
├── downloads_2024.2_11061705
│   └── downloads
└── sstate-cache_2024.2_11061705
    └── arm
```
You would set the environment variables in `environment.sh` as follows:
```bash
export PETALINUX_DOWNLOADS_PATH="$HOME/petalinux_downloads/downloads_2024.2_11061705/downloads"
```
and
```bash
export PETALINUX_SSTATE_PATH="$HOME/petalinux_downloads/sstate_arm_2024.2_11061705/arm"
```

## Optional: Running tests

You can optionally run tests for individual Verilog cores or all the custom cores used for a project using [cocotb](https://www.cocotb.org/). cocotb is a Python tool that allows you to write tests for your Verilog cores in Python, which can be run in a simulator (we use [Verilator](https://www.veripool.org/verilator/) here).

### Installing cocotb

- Use `apt` to install `cocotb` and `libpython3-dev`
```shell
sudo apt install python3-cocotb libpython3-dev
```
- Use `pip` to install `cocotb` and `cocotb_coverage`
```shell
pip install cocotb cocotb_coverage
```
- You may see a warning that `~/.local/bin` is not in your `$PATH` variable. If you're using my `~/.profile` setup above, you should see that it DOES add `~/.local/bin` to your `$PATH`, but only if the folder exists. If this is your first installation with `pip` (which is likely on a new system), the folder was only just created. If you restart your shell or system, you should see those files added to your path. You can check with
```shell
which cocotb-config
```
which should output something like:
```
/home/username/.local/bin/cocotb-config
```

### Installing Verilator

You SHOULD be able to install Verilator using `apt`, but last I checked, the version in the Ubuntu 20.04.6 repositories was too old (`4.028` but cocotb requires `4.106` -- the most recent is `5.036` as of writing, so Ubuntu is REALLY out of date).

Instead, you may need to build Verilator from source. Here's the [Verilator installation instructions](https://verilator.org/guide/latest/install.html) for that method.

Here's a slightly edited copy-paste of that section. Run these lines one-by-one in a terminal. The `git clone` line will of course clone the Verilator repo wherever you run it, so make sure you're in a directory where you want the Verilator source code to be stored (i.e. NOT in this repository's root directory).

```bash
# Prerequisites:
sudo apt install git help2man perl python3 make autoconf g++ flex bison ccache
sudo apt-get install libgoogle-perftools-dev numactl perl-doc
sudo apt-get install libfl2  # Ubuntu only (ignore if gives error)
sudo apt-get install libfl-dev  # Ubuntu only (ignore if gives error)
sudo apt-get install zlibc zlib1g zlib1g-dev  # Ubuntu only (ignore if gives error)
```
```bash
git clone https://github.com/verilator/verilator   # Only first time
```
```bash
# Every time you need to build:
unset VERILATOR_ROOT  # For bash
cd verilator
git pull         # Make sure git repository is up-to-date
```
You can then choose your Verilator version by checking out a specific commit by it's tagged version number. Some commands you can run are:
```bash
git checkout master      # Use development branch (e.g. recent bug fixes)
```
```bash
git checkout stable      # Use most recent stable release
```
```bash
git tag          # See what versions exist. Arrow keys to scroll, 'q' to quit
```
```bash
git checkout v{version}  # Switch to specified release version that's listed in the git tags, like v5.036 or v4.106
```

Finally, to build, run the following commands from inside the `verilator` directory (the one you just cloned):
```bash
autoconf         # Create ./configure script
./configure      # Configure and create Makefile
make -j `nproc`  # Build Verilator itself (if error, try just 'make')
sudo make install
```


WORK IN PROGRESS BELOW THIS POINT
---

# Building an SD card

# Example Projects

# Testing
