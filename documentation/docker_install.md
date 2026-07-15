
# Installing the tools using Docker

Instead of installing the tools directly onto a VM, this path builds a reusable dev image and keeps the toolchain in Docker volumes. The image in `docker/Dockerfile` is built once and then used in three modes via `ZYNQ_MODE`:

1. **tools** -- runs the real Xilinx GUI installer or installs extra support packages such as cocotb and Verilator into the shared tools volume.
2. **offline** -- extracts the PetaLinux offline-cache tarballs into a second volume.
3. **dev** -- the day-to-day build environment, with the repo bind-mounted and the tools/offline volumes mounted automatically.

## Cloning the repo

When using Docker, you can clone this repo directly to your host.

This repo uses git submodules, so clone with `--recurse-submodules`:

```bash
git clone --recurse-submodules https://github.com/LincolnCB/zynq_toolbox.git
cd zynq_toolbox
```

If you already cloned it without that flag, fetch the submodules afterward:

```bash
git submodule update --init --recursive
```

## Installing Docker

Pick the section for your OS. You only need to do this once per machine.

### Windows

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

### macOS

1. Download **Docker Desktop for Mac** from [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/), choosing the build that matches your chip (Apple Silicon or Intel).
2. Open the downloaded `.dmg` and drag Docker to Applications, then launch it and grant it the permissions it asks for.
3. Confirm it's working from Terminal:
   ```
   docker run hello-world
   ```
4. If you plan to run the Xilinx GUI installer (see [Setting up the Xilinx tools](#setting-up-the-xilinx-tools) below), also install [XQuartz](https://www.xquartz.org/), open **XQuartz -> Settings -> Security**, and enable "Allow connections from network clients". Restart XQuartz after changing this.

### Ubuntu

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

### Fedora

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

## Building the dev container image

With the repo cloned (see [Cloning the repo](#cloning-the-repo) above), from the repo root:

```bash
docker build \
  --build-arg BUILD_UID=$(id -u) \
  --build-arg BUILD_GID=$(id -g) \
  -t zynq-build:2024.2 \
  -f docker/Dockerfile \
  docker/
```

(On Windows without WSL2, `$(id -u)`/`$(id -g)` won't resolve -- just omit those two `--build-arg` lines; file ownership inside the container is less of a concern on Docker Desktop for Windows.)

This builds the image described in `docker/Dockerfile`: Ubuntu 20.04, bash set as the default shell, the apt packages the unified installer and PetaLinux builds need, and a non-root `builder` user (PetaLinux refuses to run as root). It does **not** contain Vivado or PetaLinux -- that's the next step.

## Preparing the Docker volumes

The Compose file expects two external Docker volumes to exist before you use the `tools` and `offline` services:

```bash
docker volume create zynq-tools
docker volume create zynq-petalinux-offline
```

## Setting up the Xilinx tools

This repo uses the AMD/Xilinx FPGA toolchain to build projects for the chips in the Zynq 7000 SoC series family. The versions listed below are the ones primarily used and tested; other versions may work as well, but you may need to add configuration files for them to projects (PetaLinux, in particular, changes its configuration files meaningfully between versions) -- see the **Configuring PetaLinux** section of the `projects/` README.

- PetaLinux (2024.2)
- Vivado (2024.2)

These can be installed together from the AMD unified installer ([2024.2 download page](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-design-tools/2024-2.html) -- select "AMD Unified Installer for FPGAs & Adaptive SoCs 2024.2: Linux Self Extracting Web Installer"). You'll need a free AMD account to download it. The same binary will be used twice for the individual installation of Vivado and PetaLinux.

1. Run the helper script with your downloaded installer:

   ```bash
   INSTALLER_BIN=/path/to/FPGAs_AdaptiveSoCs_Unified_2024.2_*.bin \
   docker compose -f docker/docker-compose.yml run --rm tools xilinx
   ```

   This starts the real Xilinx GUI installer inside the container, displaying it on your host via X11. (On Windows, run this from a WSL2 shell with an X server such as the one bundled in recent WSLg, or [VcXsrv](https://sourceforge.net/projects/vcxsrv/), running on the Windows side.)

2. On the **Select Product to Install** page, select **PetaLinux** (scroll down to the bottom), then **PetaLinux arm** under Select Edition, accept the license agreements, and leave the destination directory as the default (`/tools/Xilinx/`, creating a `PetaLinux/2024.2` folder). Click Install.

3. Run the helper again with the same installer file for the second product:

   ```bash
   INSTALLER_BIN=/path/to/FPGAs_AdaptiveSoCs_Unified_2024.2_*.bin \
   docker compose -f docker/docker-compose.yml run --rm tools xilinx
   ```

   Select **Vivado**, then **Vivado ML Standard** under Select Edition. On the components page, uncheck everything, then re-check:
   - **DocNav** (optional, for in-app documentation)
   - Under **Devices -> Production Devices -> SoCs**, check **Zynq-7000** (it's fine that it says "limited support")

   Accept the license agreements, leave the destination as default (`/tools/Xilinx/`, creating a `Vivado/2024.2` folder), and click Install.

If you also want the optional Python/Verilator support packages in the same tools volume, you can install them with:

```bash
docker compose -f docker/docker-compose.yml run --rm tools cocotb
docker compose -f docker/docker-compose.yml run --rm tools verilator stable
```

You can confirm the contents of the zynq-tools volume any time with:

```bash
docker run --rm -v zynq-tools:/tools/Xilinx ubuntu:20.04 ls -la /tools/Xilinx
```

You won't need to touch this volume again unless you're installing a different tools version, and you never need to re-run the installer just because you rebuilt or removed a dev container -- the volume is independent of any container.

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

Mount the two directories into the container read-only, and pass the same variables as env vars at `docker run` time instead:

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

If you want the offline build cache available inside the dev container, extract the tarballs into the `zynq-petalinux-offline` volume:

```bash
PETALINUX_DOWNLOADS_TAR=/path/to/downloads.tar.gz \
PETALINUX_SSTATE_TAR=/path/to/sstate.tar.gz \
docker compose -f docker/docker-compose.yml run --rm offline
```

The helper script expects the two tarballs and will place their contents under `downloads/` and `arm/` inside the volume, which the dev container will discover automatically.

## Optional: Running tests

You can optionally run tests for individual Verilog cores or all the custom cores used for a project using [cocotb](https://www.cocotb.org/). cocotb is a Python tool that allows you to write tests for your Verilog cores in Python, which can be run in a simulator (we use [Verilator](https://www.veripool.org/verilator/) here).

### Installing cocotb

Nothing to do -- `cocotb` and its apt/pip dependencies are already baked into the dev image.

### Installing Verilator

You SHOULD be able to install Verilator using `apt`, but Ubuntu 20.04's packaged version is too old (`4.028`, when cocotb requires `4.106`+ -- the most recent is `5.036` as of writing). Either way, you'll need to build it from source, following [Verilator's install instructions](https://verilator.org/guide/latest/install.html).

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

## Running the dev container

From the repo root:

```bash
docker compose -f docker/docker-compose.yml run --rm dev
```

This launches the dev environment as the `builder` user inside `/workspace/zynq_toolbox`. The `docker/entrypoint.sh` script runs automatically on container start and exports `ZYNQ_TOOLBOX`, `PETALINUX_PATH`, and `VIVADO_PATH`, sources Vivado's `settings64.sh`, and (re)writes `~/.Xilinx/Vivado/Vivado_init.tcl` for you. Confirm it worked:

```bash
echo $ZYNQ_TOOLBOX $PETALINUX_PATH $VIVADO_PATH
which vivado petalinux-create
```

Because the repo directory is bind-mounted rather than copied into the image, anything the container writes into it (build outputs under `out/` and `tmp/`, generated config files) shows up directly on your host, and nothing is lost when the container exits -- `--rm` just means Docker throws away the *container*, not the mounted data.

With this done, your Docker install is complete -- continue to [Optional: Makefile variable defaults](#optional-makefile-variable-defaults) or straight to [Building an SD card](#building-an-sd-card).

---
