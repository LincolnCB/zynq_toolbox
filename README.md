***Updated 2026-07-13***

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
- `docker`: Only used if you're following the Docker installation path. Contains the `Dockerfile`, the `entrypoint.sh` that wires up the tool environment automatically, the `install-xilinx-tools.sh` one-time installer helper, and a `docker-compose.yml` convenience wrapper. See [Option B: Installing the tools in Docker](#option-b-installing-the-tools-in-docker).
- `example_cores`: Contains example/custom cores used in the scripted build of the FPGA system, separated by "vendor" (original author). You can add your own custom cores here in your own folder, following the same structure as the others.
- `kernel_modules`: Contains kernel modules that can be included in the Linux kernel build for projects.
- `projects`: Contains the projects that can be built with this repo. Each project has its own folder, and is mainly defined by its `block_design.tcl` file, which defines the FPGA system's block design. Each project will also need folders under `cfg` that define compatibility with different boards, and can have a few other special folders that augment the build process.
- `scripts`: Contains scripts that are used to build projects, separated by category (`check`, `make`, `petalinux`, and `vivado`).

There are some temporary, untracked folders that contain the intermediate and final build results: `out` and `tmp`. In addition, there's a temporary `tmp_reports` folder that contains Vivado reports for resource utilization.

Finally, there's some files:

- `.gitmodules`: Declares this repo's git submodules. Make sure to clone with `--recurse-submodules` or run `git submodule update --init --recursive` afterward -- see [Cloning the repo](#cloning-the-repo).
- `environment.sh.example`: A template for environment variables, used by the **VM** installation path as explained in [Profile setup](#profile-setup). If you're following the **Docker** path, this file is generated for you automatically inside the container, and you generally won't need to touch it.
- `make_defaults.mk.example`: Can optionally be copied as explained in [Optional: Makefile variable defaults](#optional-makefile-variable-defaults).
- `Makefile`: The main Makefile that is used to build everything, see [Building an SD card](#building-an-sd-card).

# Getting started

## Required tools

This repo uses the AMD/Xilinx FPGA toolchain to build projects for the chips in the Zynq 7000 SoC series family. The versions listed below are the ones primarily used and tested; other versions may work as well, but you may need to add configuration files for them to projects (PetaLinux, in particular, changes its configuration files meaningfully between versions) -- see the **Configuring PetaLinux** section of the `projects/` README.

- PetaLinux (2024.2)
- Vivado (2024.2)

These can be installed together from the AMD unified installer ([2024.2 download page](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-design-tools/2024-2.html) -- select "AMD Unified Installer for FPGAs & Adaptive SoCs 2024.2: Linux Self Extracting Web Installer"). You'll need a free AMD account to download it. The same binary will be used twice for the individual installation of Vivado and PetaLinux.

> If you're using a VM, make sure to download this file to the VM. For Docker, you can download the binary to your host.

## Choosing an installation method

|    | VM    | Docker |
|----|-------|--------|
| Manual steps | Significant | More automated |
| Where the repo lives | Directly on the VM's virtual disk | On your host machine |
| Where the tools live | Directly on the VM's virtual disk | In an isolated Docker volume, separate from your host|
| Host footprint | One large VM disk image | Repo folder + a small docker image + a large but self-contained Docker volume |
| Rebuilding your dev environment | Usually means redoing the whole process | Rebuild the container any time; the tools volume is untouched |
| GUI for installer and Vivado | Native, since you're on the VM's desktop | Forwarded from the container to your host via X11 (one-time setup) |

Both paths use the exact same `.bin` installer and produce the exact same `/tools/Xilinx/PetaLinux/2024.2/` and `/tools/Xilinx/Vivado/2024.2/` layout, and every step past "Getting started" (building, testing, etc.) works identically either way, with a couple of Docker-specific notes called out inline where they come up.

## Cloning the repo

This repo uses git submodules, so clone with `--recurse-submodules`:

```bash
git clone --recurse-submodules https://github.com/LincolnCB/zynq_toolbox.git
cd zynq_toolbox
```

If you already cloned it without that flag, fetch the submodules afterward:

```bash
git submodule update --init --recursive
```

If you're going the VM route, do this clone *inside the VM*. If you're going the Docker route, do this clone on your *host* -- the repo directory gets bind-mounted into the dev container, so it needs to live somewhere persistent on your actual disk, not inside a container.

---

## Option A: Installing the tools in a VM

The tools' supported OSes are slightly limited. For the recommended versions listed above, I used a VM running [Ubuntu 20.04.6 (Desktop image)](https://www.releases.ubuntu.com/focal/) with 200 GB of storage/disk space, 16 GB of RAM/memory, and 8 CPU cores. If you're running on a Mac with an M1/M2 or other non-x86 chip, you may need to be picky with your VM software ([UTM](https://mac.getutm.app/) seems to be the recommended option -- make sure to select "iso image" when selecting the downloaded Ubuntu ISO). In terms of installing Ubuntu on the VM, I recommend a "Minimal Install" and not to "Download Updates" to keep it as simple and close to the original, supported edition as possible.

My process is explained below, but is definitely not the only way to do this. Do this and everything else on the VM you want the tools installed to.

### Unified installer

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

### Installing PetaLinux

On the "**Select Product to Install**" page, scroll to the bottom and select "**PetaLinux**" and click Next. This repo is primarily focused on the Zynq7000 series SoCs, so you can select "**PetaLinux arm**" under "**Select Edition to Install**" and click Next. Accept the License Agreements and click Next. You can leave everything as default under "**Select Destination Directory**" (the default will be `/tools/Xilinx/` and will create a `PetaLinux/2024.2` directory). Click Next and then Install.

### Installing Vivado

Running the unified installer again, back on the "**Select Product to Install**" page, "**Vivado**" should be the second option. Select it and click Next. Under "**Select Edition to Install**", select "**Vivado ML Standard**" and click Next. The next section, "**Vivado ML Standard**", allows you to trim the installation size to only the components needed. First, uncheck everything you can. You can then check the following options:

- **DocNav** (optional) for looking at documentation in the Vivado GUI. Documentation can also be found online.
- Under **Devices** -> **Production Devices** -> **SoCs** check **Zynq-7000** (you may need to expand the sections to see this. It's fine that it says "limited support").

Click Next. Accept the License Agreements and click Next. Just like with PetaLinux, you can leave everything as default under "**Select Destination Directory**" (the default will be `/tools/Xilinx/` and will create a `Vivado/2024.2` directory). Click Next and then Install.

### Changing your default shell to bash

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

### Profile setup

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

#### Which bash file to add the source line to?

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

### Vivado init script

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

With this done, your VM install is complete -- skip ahead to [Optional: Makefile variable defaults](#optional-makefile-variable-defaults) or straight to [Building an SD card](#building-an-sd-card).

---

## Option B: Installing the tools in Docker

Instead of installing the tools directly onto a VM, this path sets up:

1. **Docker**, on whatever host OS you're using.
2. A **dev container image**, built from `docker/Dockerfile`, containing just the OS packages the tools need.
3. A **Docker volume** (`xilinx-tools`), containing the actual PetaLinux + Vivado install, done once via the real Xilinx GUI installer and reusable across containers indefinitely.

### Installing Docker

Pick the section for your OS. You only need to do this once per machine.

#### Windows

1. Confirm virtualization is enabled in your BIOS/UEFI (it usually is by default on modern machines) and that you're on Windows 10 (build 19045+) or Windows 11.
2. Install WSL2 if you don't already have it. Open PowerShell as Administrator and run:
   ```
   wsl --install
   ```
   Reboot if prompted.
3. Download and install **Docker Desktop for Windows** from [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/).
4. Launch Docker Desktop, and in **Settings -> General**, confirm "Use the WSL 2 based engine" is checked.
5. Open a terminal (PowerShell, Windows Terminal, or a WSL2 shell) and confirm it's working:
   ```
   docker run hello-world
   ```

You'll run all the commands in this README from either PowerShell, Windows Terminal, or (recommended, since the rest of this guide uses Unix-style paths and shell syntax) a WSL2 Ubuntu shell.

#### macOS

1. Download **Docker Desktop for Mac** from [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/), choosing the build that matches your chip (Apple Silicon or Intel).
2. Open the downloaded `.dmg` and drag Docker to Applications, then launch it and grant it the permissions it asks for.
3. Confirm it's working from Terminal:
   ```
   docker run hello-world
   ```
4. If you plan to run the Xilinx GUI installer (see [Setting up the tools volume](#setting-up-the-tools-volume) below), also install [XQuartz](https://www.xquartz.org/), open **XQuartz -> Settings -> Security**, and enable "Allow connections from network clients". Restart XQuartz after changing this.

#### Ubuntu

Use Docker's official apt repository rather than the `docker.io` package in Ubuntu's own repos, which tends to lag behind. Docker recommends removing existing installations that may come with the distro.

```bash
# Remove any old/conflicting packages first
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  sudo apt-get remove -y $pkg 2>/dev/null || true
done

# Add Docker's official GPG key and repository
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine, CLI, and plugins
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Let your user run Docker without `sudo`, then log out and back in (or reboot) for it to take effect:

```bash
sudo usermod -aG docker $USER
```

Confirm it's working:

```bash
docker run hello-world
```

#### Fedora

Docker recommends removing existing installations that may come with the distro.

```bash
sudo dnf -y remove docker docker-client docker-client-latest docker-common \
  docker-latest docker-latest-logrotate docker-logrotate docker-selinux \
  docker-engine-selinux docker-engine podman-docker 2>/dev/null || true

sudo dnf -y install dnf-plugins-core
sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

Log out and back in (or reboot), then confirm it's working:

```bash
docker run hello-world
```

> These commands reflect Docker's official install docs as of mid-2026. If any step errors out, check [docs.docker.com/engine/install](https://docs.docker.com/engine/install/) for your OS -- Docker occasionally tweaks the exact setup commands.

### Building the dev container image

With the repo cloned (see [Cloning the repo](#cloning-the-repo) above), from the repo root:

```bash
docker build \
  --build-arg BUILD_UID=$(id -u) \
  --build-arg BUILD_GID=$(id -g) \
  -t zynq-toolbox-dev:2024.2 \
  docker/
```

(On Windows without WSL2, `$(id -u)`/`$(id -g)` won't resolve -- just omit those two `--build-arg` lines; file ownership inside the container is less of a concern on Docker Desktop for Windows.)

This builds the image described in `docker/Dockerfile`: Ubuntu 20.04, bash set as the default shell, the apt packages the unified installer and PetaLinux builds need, and a non-root `builder` user (PetaLinux refuses to run as root). It does **not** contain Vivado or PetaLinux -- that's the next step.

### Setting up the tools volume

This is the Docker equivalent of the VM path's "Unified installer" step, and like that step, it only needs to be done once (or once per Xilinx tools version you want available).

1. Make the script executable and run it with your downloaded installer:

   ```bash
   chmod +x docker/install-xilinx-tools.sh
   ./docker/install-xilinx-tools.sh /path/to/FPGAs_AdaptiveSoCs_Unified_2024.2_*.bin
   ```

   This creates a Docker volume named `xilinx-tools` and opens the real Xilinx GUI installer inside a throwaway container, displaying it on your host via X11. (On Windows, run this from a WSL2 shell with an X server such as the one bundled in recent WSLg, or [VcXsrv](https://sourceforge.net/projects/vcxsrv/), running on the Windows side.)

2. On the **Select Product to Install** page, select **PetaLinux** (scroll down to the bottom), then **PetaLinux arm** under Select Edition, accept the license agreements, and leave the destination directory as the default (`/tools/Xilinx/`, creating a `PetaLinux/2024.2` folder). Click Install.

3. Run the script again with the same installer file for the second product:

   ```bash
   ./docker/install-xilinx-tools.sh /path/to/FPGAs_AdaptiveSoCs_Unified_2024.2_*.bin
   ```

   Select **Vivado**, then **Vivado ML Standard** under Select Edition. On the components page, uncheck everything, then re-check:
   - **DocNav** (optional, for in-app documentation)
   - Under **Devices -> Production Devices -> SoCs**, check **Zynq-7000** (it's fine that it says "limited support")

   Accept the license agreements, leave the destination as default (`/tools/Xilinx/`, creating a `Vivado/2024.2` folder), and click Install.

When both finish, the `xilinx-tools` volume contains the same `/tools/Xilinx/PetaLinux/2024.2/` and `/tools/Xilinx/Vivado/2024.2/` layout the VM path produces -- just living in an isolated Docker volume instead of directly on a disk. You can confirm its contents any time with:

```bash
docker run --rm -v xilinx-tools:/tools/Xilinx ubuntu:20.04 ls -la /tools/Xilinx
```

You won't need to touch this volume again unless you're installing a different tools version, and you never need to re-run the installer just because you rebuilt or removed a dev container -- the volume is independent of any container.

### Running the dev container

From the repo root:

```bash
docker run -it --rm \
  -v xilinx-tools:/tools/Xilinx \
  -v "$(pwd):/workspace/zynq_toolbox" \
  zynq-toolbox-dev:2024.2
```

Or, using the included Compose file (does the same thing with less typing, and rebuilds the image automatically if `docker/Dockerfile` changed):

```bash
docker compose -f docker/docker-compose.yml run --rm dev
```

Either way, you'll land in a bash shell as the `builder` user inside `/workspace/zynq_toolbox`. This replaces the VM path's **Profile setup** and **Vivado init script** steps -- `docker/entrypoint.sh` runs automatically on container start and exports `ZYNQ_TOOLBOX`, `PETALINUX_PATH`, and `VIVADO_PATH`, sources Vivado's `settings64.sh`, and (re)writes `~/.Xilinx/Vivado/Vivado_init.tcl` for you. Confirm it worked:

```bash
echo $ZYNQ_TOOLBOX $PETALINUX_PATH $VIVADO_PATH
which vivado petalinux-create
```

Because the repo directory is bind-mounted rather than copied into the image, anything the container writes into it (build outputs under `out/` and `tmp/`, generated config files) shows up directly on your host, and nothing is lost when the container exits -- `--rm` just means Docker throws away the *container*, not the mounted data.

> **One Docker-vs-VM difference worth knowing:** a VM's disk keeps whatever you install on it. A container does not -- if you `apt install` something or build a tool by hand *inside a running container* without it living in a mounted volume, it disappears the next time you start a fresh container from the image. This comes up again in [Testing](#testing) below, for Verilator specifically.

With this done, your Docker install is complete -- continue to [Optional: Makefile variable defaults](#optional-makefile-variable-defaults) or straight to [Building an SD card](#building-an-sd-card).

---

## Optional: Makefile variable defaults

The Makefile is set up to use the variables `PROJECT`, `BOARD`, and `BOARD_VER` to determine which project, board, and board version to build, as well as a couple others (see [Building an SD card](#building-an-sd-card), [Building a different board, board version, or project](#building-a-different-board-board-version-or-project), [Building PetaLinux offline](#building-petalinux-offline), and [Script targets](#script-targets) for more information). To set personal default values for these variables, copy

```
make_defaults.mk.example
```

into the file

```
make_defaults.mk
```

and make your edits there, inside your repo checkout (VM path: directly on the VM; Docker path: on the host -- it'll be visible from inside the container too, since the whole repo is bind-mounted). Just like `environment.sh`, only the example file is tracked, so you can edit `make_defaults.mk` without worrying about it being overwritten by a `git pull` or similar command.

## Optional: PetaLinux offline build setup

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

**VM path:** set the following in your `environment.sh`:

```
export PETALINUX_DOWNLOADS_PATH="$HOME/petalinux_downloads/downloads_2024.2_11061705/downloads"
export PETALINUX_SSTATE_PATH="$HOME/petalinux_downloads/sstate-cache_2024.2_11061705/arm"
```

**Docker path:** mount the two directories into the container read-only, and pass the same variables as env vars at `docker run` time instead:

```bash
docker run -it --rm \
  -v xilinx-tools:/tools/Xilinx \
  -v "$(pwd):/workspace/zynq_toolbox" \
  -v ~/petalinux_downloads/downloads_2024.2_11061705/downloads:/workspace/petalinux_downloads:ro \
  -v ~/petalinux_downloads/sstate-cache_2024.2_11061705/arm:/workspace/petalinux_sstate:ro \
  -e PETALINUX_DOWNLOADS_PATH=/workspace/petalinux_downloads \
  -e PETALINUX_SSTATE_PATH=/workspace/petalinux_sstate \
  zynq-toolbox-dev:2024.2
```

With these variables set (either way), include `OFFLINE=true` in the `make` command -- see [Building PetaLinux offline](#building-petalinux-offline).

## Optional: Running tests

You can optionally run tests for individual Verilog cores or all the custom cores used for a project using [cocotb](https://www.cocotb.org/). cocotb is a Python tool that allows you to write tests for your Verilog cores in Python, which can be run in a simulator (we use [Verilator](https://www.veripool.org/verilator/) here).

### Installing cocotb

**VM path:**

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

**Docker path:** nothing to do -- `cocotb` and its apt/pip dependencies are already baked into the dev image.

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

**Docker path:** the steps are the same, but *where* you run them matters, because containers don't persist ad hoc changes the way a VM disk does (see the note in [Running the dev container](#running-the-dev-container)):

- **Persistent (recommended)**: build it into a location that's actually mounted, not just the container's own filesystem -- either inside your bind-mounted repo checkout (e.g. a `.verilator/` subfolder, which you'd want to add to `.gitignore` if it isn't already covered), or a separate named volume mounted every time (`-v verilator-build:/opt/verilator`). Either way it survives container recreation.
- **Ad hoc**: build it directly inside a running container with no extra mount. Fine for a one-off test, but you'll rebuild it from scratch the next time you start a fresh container.

From inside the container, in a persistent location:

```bash
sudo apt-get update
sudo apt-get install -y help2man perl flex bison ccache libgoogle-perftools-dev numactl perl-doc libfl2 libfl-dev zlibc zlib1g

git clone https://github.com/verilator/verilator   # only the first time
cd verilator
git pull
unset VERILATOR_ROOT
git checkout stable                                # or a specific tag from `git tag`
autoconf
./configure
make -j$(nproc)
sudo make install
```

Since `sudo make install` installs into the container's own `/usr/local`, that part doesn't persist across container recreation either way -- add `export PATH="$HOME/verilator/bin:$PATH"` (pointing at wherever you built it) to your shell, or just re-run `sudo make install` after `git pull` when you bump versions, rather than relying on a from-scratch container having it.

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

If you set up [Optional: PetaLinux offline build setup](#optional-petalinux-offline-build-setup) above, you can include the `OFFLINE=true` variable in the `make` command to use the local files instead of downloading them. For example, to build the Rev D Shim firmware for the Snickerdoodle Black with offline PetaLinux, you can run:

```
make OFFLINE=true
```

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

## EX05 -- DMA

This example project covers the Direct Memory Access (DMA) interface, which allows the PS to transfer data to and from the PL through the off-chip DDR memory.

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