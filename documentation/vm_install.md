# Installing the tools in a VM

The tools' supported OSes are slightly limited. For the recommended versions listed above, I used a VM running [Ubuntu 20.04.6 (Desktop image)](https://www.releases.ubuntu.com/focal/) with 200 GB of storage/disk space, 16 GB of RAM/memory, and 8 CPU cores. If you're running on a Mac with an M1/M2 or other non-x86 chip, you may need to be picky with your VM software ([UTM](https://mac.getutm.app/) seems to be the recommended option -- make sure to select "iso image" when selecting the downloaded Ubuntu ISO). In terms of installing Ubuntu on the VM, I recommend a "Minimal Install" and not to "Download Updates" to keep it as simple and close to the original, supported edition as possible.

My process is explained below, but is definitely not the only way to do this. Do this and everything else on the VM you want the tools installed to.

## Cloning the repo

Make sure to clone this repo inside of your VM.

This repo uses git submodules, so clone with `--recurse-submodules`:

```bash
git clone --recurse-submodules https://github.com/LincolnCB/zynq_toolbox.git
cd zynq_toolbox
```

If you already cloned it without that flag, fetch the submodules afterward:

```bash
git submodule update --init --recursive
```

## Required tools

This repo uses the AMD/Xilinx FPGA toolchain to build projects for the chips in the Zynq 7000 SoC series family. The versions listed below are the ones primarily used and tested; other versions may work as well, but you may need to add configuration files for them to projects (PetaLinux, in particular, changes its configuration files meaningfully between versions) -- see the **Configuring PetaLinux** section of the `projects/` README.

- PetaLinux (2024.2)
- Vivado (2024.2)

These can be installed together from the AMD unified installer ([2024.2 download page](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-design-tools/2024-2.html) -- select "AMD Unified Installer for FPGAs & Adaptive SoCs 2024.2: Linux Self Extracting Web Installer"). You'll need a free AMD account to download it. The same binary will be used twice for the individual installation of Vivado and PetaLinux.

## Unified installer

Follow the documentation [here](https://docs.amd.com/r/en-US/ug1144-petalinux-tools-reference-guide/Installation-Steps) -- make sure the dropdown version at the top of the documentation matches the version you're using.

You should make sure the system has the required libraries. From a stock Ubuntu 20.04.6 install, you'll need to install the following packages with `sudo apt install` to make PetaLinux and Vivado install successfully:

```
sudo apt install gcc xterm autoconf libtool texinfo zlib1g-dev gcc-multilib build-essential libncurses5-dev libtinfo5
```

To run the unified installer, you will likely need to make it executable first. This is done by running (from the folder containing the installer, which will likely be your Downloads folder):

```
chmod +x FPGAs_AdaptiveSoCs_Unified_2024.2_1113_1001_Lin64.bin
```

From there, you can run the installer (this will need `sudo` permissions to write to the recommended default installation directory, which is `/tools/Xilinx/`).

```
sudo ./FPGAs_AdaptiveSoCs_Unified_2024.2_1113_1001_Lin64.bin
```

This will open a GUI installer. You will need to log in with your AMD account again. This will take you to the "**Select Product to Install**" page. You will need to run this installer twice, once for each of the two tools (PetaLinux and Vivado). It's recommended to start with PetaLinux, as it is smaller and quicker to install.

## Installing PetaLinux

On the "**Select Product to Install**" page, scroll to the bottom and select "**PetaLinux**" and click Next. This repo is primarily focused on the Zynq7000 series SoCs, so you can select "**PetaLinux arm**" under "**Select Edition to Install**" and click Next. Accept the License Agreements and click Next. You can leave everything as default under "**Select Destination Directory**" (the default will be `/tools/Xilinx/` and will create a `PetaLinux/2024.2` directory). Click Next and then Install.

## Installing Vivado

Running the unified installer again, back on the "**Select Product to Install**" page, "**Vivado**" should be the second option. Select it and click Next. Under "**Select Edition to Install**", select "**Vivado ML Standard**" and click Next. The next section, "**Vivado ML Standard**", allows you to trim the installation size to only the components needed. First, uncheck everything you can. You can then check the following options:

- **DocNav** (optional) for looking at documentation in the Vivado GUI. Documentation can also be found online.
- Under **Devices** -> **Production Devices** -> **SoCs** check **Zynq-7000** (you may need to expand the sections to see this. It's fine that it says "limited support").

Click Next. Accept the License Agreements and click Next. Just like with PetaLinux, you can leave everything as default under "**Select Destination Directory**" (the default will be `/tools/Xilinx/` and will create a `Vivado/2024.2` directory). Click Next and then Install.

## Changing your default shell to bash

PetaLinux requires the default shell to be bash. In Ubuntu 20.04.6 (and most other Ubuntu versions), the default shell is Dash. The default shell is the `/bin/sh` file, which is a symlink to the binary of another shell. You can check your current default shell by running:

```
ls -l /bin/sh
```

This will output something like:

```
lrwxrwxrwx 1 root root 4 Mar 31  2024 /bin/sh -> dash
```

This means that the default shell is currently Dash.

To change it to bash, you can run:

```
sudo ln -sf /bin/bash /bin/sh
```

which overrides the symlink to point to bash instead of Dash.

Checking again with `ls -l /bin/sh` should now output:

```
lrwxrwxrwx 1 root root 9 Apr 29 01:13 /bin/sh -> /bin/bash
```

## Profile setup

With this repository cloned into your VM (e.g. `/home/username/zynq_toolbox` or something similar), you will need to set up some environment variables and modify the Vivado init script to use this repo's scripts. At the top level of this repository, you will find a file named

```
environment.sh.example
```

This is a template file for the environment variables that you need to set up. Copy this file and name the copy

```
environment.sh
```

This file will be used by the repo, but is not tracked by git, so you can modify it without worrying about it being overwritten by a `git pull` or similar command.

You will need to edit the following variables in this file to match your setup:

- `ZYNQ_TOOLBOX`: The path to the repository root directory (e.g. `/home/username/zynq_toolbox`, as above)
- `PETALINUX_PATH`: The path to the PetaLinux installation directory (by default, this will be `/tools/Xilinx/PetaLinux/2024.2/tool`)
- `PETALINUX_VERSION`: The version of PetaLinux you are using (e.g. `2024.2`)
- `VIVADO_PATH`: The path to the Vivado installation directory (by default, this will be `/tools/Xilinx/Vivado/2024.2`)

The remaining lines are optional or do not need to be changed:

- `source $VIVADO_PATH/settings64.sh`: This line sources a Vivado script that sets up the terminal environment for Vivado. This should be left as is.
- `PETALINUX_DOWNLOADS_PATH`/`PETALINUX_SSTATE_PATH`: These are optional variables only needed if you want to do offline builds with PetaLinux. See [Optional: PetaLinux offline build setup](#optional-petalinux-offline-build-setup) below for more information.

With `environment.sh` set up, you will need to source it in your shell. Add the following line to one of the files that is sourced in new bash terminals, where `[path_to_zynq_toolbox]` is the path to the root of this repository (e.g. `/home/username/zynq_toolbox`):

```
source [path_to_zynq_toolbox]/environment.sh
```

### Which bash file to add the source line to?

Feel free to skip this section if you already know how to set up your bash profile files.

bash has a number of profile files: `~/.bashrc`, `~/.bash_profile`, and `~/.profile` are common, as well as the lesser-used `/etc/profile` and `~/.bash_login`. Here's a short summary of [what each of those files does](https://www.baeldung.com/linux/bashrc-vs-bash-profile-vs-profile).

A common preference is to only have `~/.profile` and `~/.bashrc`. Here's how that works:

When logging in with a terminal, you're opening an *interactive, login* shell. In this case, bash will try to source the first of whichever is present, in order: `~/.bash_profile`, then `~/.bash_login`, then `~/.profile`. `~/.profile` is also used by some other shells like Dash.

When opening a new terminal window, you're opening an *interactive, non-login* shell. In this case, bash will source `~/.bashrc`.

`~/.profile` may contain lines sourcing `~/.bashrc`, which you'll want to make sure only run in interactive shells. To do this, replace any line that does so:

```
. "$HOME/.bashrc"
```

with:

```
if [[ $- == *i* ]]; then . "$HOME/.bashrc"; fi
```

which checks if the `$-` variable (containing single letter flags about the terminal status) contains `i` (interactive).

All of this gives the following `~/.profile`, in its entirety:

```
# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
if [ -n "$bash_VERSION" ]; then
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
source $HOME/zynq_toolbox/environment.sh
```

However, `~/.profile` is only sourced if `~/.bash_profile` and `~/.bash_login` don't exist. If `~/.bash_profile` already exists, you can delete it. If it needs to exist, just source `~/.profile` in it.

```
#~/.bash_profile
# Just source .profile
. "$HOME/.profile"
```

You can do similarly with `~/.bash_login` if it exists, but it's rarely used.

## Vivado init script

The final required step is to pass some of the environment variables to Vivado. This is done by modifying the Vivado init script to source the `scripts/vivado/repo_paths.tcl` script from this repository. The Vivado init script can be located in one of three places. Vivado checks each in order (each overriding the last one):

- Install directory (`/tools/Xilinx/Vivado/<version>/Vivado_init.tcl` by default)
- Particular Vivado version (`~/.Xilinx/Vivado/<version>/Vivado_init.tcl`)
- Overall Vivado (`~/.Xilinx/Vivado/Vivado_init.tcl`)

For personal use, set it in the last location to override everything else. Go to that location and create the `Vivado_init.tcl` file if it doesn't exist, or edit it if it does. It should look like:

```
# Example ~/.Xilinx/Vivado/Vivado_init.tcl:
# Set up Rev D configuration
set zynq_toolbox $::env(ZYNQ_TOOLBOX)
source $zynq_toolbox/scripts/vivado/repo_paths.tcl
```

With this done, your VM install is complete. You can install the optional tools/files below (some highly recommended) or just continue on to [Makefile variable defaults](../README.md#makefile-variable-defaults) and **make sure to set your `MODE` to `vm`**.


## Optional (RECOMMENDED): PetaLinux offline build setup

The PetaLinux build process requires downloading a lot of files from the internet, which can be slow and unreliable. Depending on your network connection, this could add upwards of ten minutes to the build time. If you want a more reliable build process, you can download these files once and reuse them.

For PetaLinux 2024.2, download from the [AMD download center](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/embedded-design-tools/2024-2.html), under **PetaLinux Tools sstate-cache Artifacts** (you can ignore the final section, Update 1). You'll need two files:

- `arm sstate-cache` (TAR/GZIP - ~9 GB)
- `Downloads` (TAR/GZIP - ~59 GB)

Extract these to some directory on your system. Each archive has a simply named directory at the top, `downloads` and `arm`. For example:

```
~/petalinux_downloads
├── downloads_2024.2_11061705
│   └── downloads
└── sstate-cache_2024.2_11061705
    └── arm
```

Set the following in your `environment.sh`:

```
export PETALINUX_DOWNLOADS_PATH="$HOME/petalinux_downloads/downloads_2024.2_11061705/downloads"
export PETALINUX_SSTATE_PATH="$HOME/petalinux_downloads/sstate-cache_2024.2_11061705/arm"
```

With these variables set, include `OFFLINE=true` in the `make` command -- see [Building PetaLinux offline](../README.md#building-petalinux-offline).

## Optional: Running tests

You can optionally run tests for individual Verilog cores or all the custom cores used for a project using [cocotb](https://www.cocotb.org/). cocotb is a Python tool that allows you to write tests for your Verilog cores in Python, which can be run in a simulator (we use [Verilator](https://www.veripool.org/verilator/) here).

### Installing cocotb

- Use `apt` to install `cocotb` and `libpython3-dev`:
  ```
  sudo apt install python3-cocotb libpython3-dev
  ```
- Use `pip` to install `cocotb` and `cocotb_coverage`:
  ```
  pip install cocotb cocotb_coverage
  ```
- You may see a warning that `~/.local/bin` is not in your `$PATH` variable. If you're using the `~/.profile` setup from [Profile setup](#profile-setup) above, it DOES add `~/.local/bin` to your `$PATH`, but only if the folder already exists. If this is your first `pip` install, the folder was only just created -- restart your shell or system and it should pick it up. Check with:
  ```
  which cocotb-config
  ```
  which should output something like `/home/username/.local/bin/cocotb-config`.

### Installing Verilator

You SHOULD be able to install Verilator using `apt`, but Ubuntu 20.04's packaged version is too old (`4.028`, when cocotb requires `4.106`+ -- the most recent is `5.036` as of writing). Either way, you'll need to build it from source, following [Verilator's install instructions](https://verilator.org/guide/latest/install.html).

**VM path:** run these lines one-by-one in a terminal. The `git clone` will of course clone the Verilator repo wherever you run it, so make sure you're in a directory where you want the source code stored (i.e. NOT in this repository's root directory).

```
# Prerequisites:
sudo apt install git help2man perl python3 make autoconf g++ flex bison ccache
sudo apt-get install libgoogle-perftools-dev numactl perl-doc
sudo apt-get install libfl2  # Ubuntu only (ignore if gives error)
sudo apt-get install libfl-dev  # Ubuntu only (ignore if gives error)
sudo apt-get install zlibc zlib1g zlib1g-dev  # Ubuntu only (ignore if gives error)
```

```
git clone https://github.com/verilator/verilator   # Only first time
```

```
# Every time you need to build:
unset VERILATOR_ROOT  # For bash
cd verilator
git pull         # Make sure git repository is up-to-date
```

Choose your Verilator version by checking out a specific tagged commit:

```
git checkout master      # Use development branch (e.g. recent bug fixes)
git checkout stable      # Use most recent stable release
git tag                  # See what versions exist. Arrow keys to scroll, 'q' to quit
git checkout v{version}  # Switch to a specific tagged release, like v5.036 or v4.106
```

Finally, build from inside the `verilator` directory:

```
autoconf         # Create ./configure script
./configure      # Configure and create Makefile
make -j `nproc`  # Build Verilator itself (if error, try just 'make')
sudo make install
```

---
