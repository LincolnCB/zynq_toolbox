# Installing the tools using Docker

Instead of installing the tools directly onto a VM, this path keeps each tool in its
own standalone container, with the large tool installs living in their own Docker
volumes rather than baked into any image.

The repo itself is bind-mounted into whichever container is running, so build
outputs (`tmp/`, `out/`) stay on your host.

You don't have to run these containers by hand -- once they're built and the tool
volumes are populated, the top-level `Makefile` drives all three automatically when
you set `MODE=container` (see [Running builds](#running-builds) below). The manual
`docker compose run` commands in this doc are mainly useful for the one-time tool
installation and for interactive debugging inside a given tool's container.

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

## Building the runner images

With the repo cloned (see [Cloning the repo](#cloning-the-repo) above), from the repo root, build all three images at once:

```bash
BUILD_UID=$(id -u) BUILD_GID=$(id -g) \
  docker compose -f scripts/docker/docker-compose.yml build
```

(On Windows without WSL2, `$(id -u)`/`$(id -g)` won't resolve -- just omit that first line; file ownership inside the containers is less of a concern on Docker Desktop for Windows, and the images fall back to a default UID/GID of 1000.)

Or build just one at a time if you only need it right now, e.g.:

```bash
BUILD_UID=$(id -u) BUILD_GID=$(id -g) docker compose -f scripts/docker/docker-compose.yml build vivado
```

Each image is deliberately thin -- `vivado.Dockerfile` and `petalinux.Dockerfile` contain only the OS packages their respective tool needs to run, not the tool itself; Vivado and PetaLinux are installed once into separate Docker volumes in the next step, then mounted read-only at runtime. `cocotb.Dockerfile` is the exception -- cocotb and Verilator are small enough to bake directly into that image, so there's no separate volume for it.

## Setting up the Xilinx tools

This repo uses the AMD/Xilinx FPGA toolchain to build projects for the chips in the Zynq 7000 SoC series family. The versions listed below are the ones primarily used and tested; other versions may work as well, but you may need to add configuration files for them to projects (PetaLinux, in particular, changes its configuration files meaningfully between versions) -- see the **Configuring PetaLinux** section of the `projects/` README.

- PetaLinux (2024.2)
- Vivado (2024.2)

These can be installed together from the AMD unified installer ([2024.2 download page](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-design-tools/2024-2.html) -- select "AMD Unified Installer for FPGAs & Adaptive SoCs 2024.2: Linux Self Extracting Web Installer"). You'll need a free AMD account to download it. The same installer binary is used for both products, once per product, each writing into its own volume.

1. Install Vivado, into the `vivado-tools` volume:

   ```bash
   ./scripts/docker/install-vivado.sh /path/to/FPGAs_AdaptiveSoCs_Unified_2024.2.bin
   ```

   This starts the real Xilinx GUI installer inside a throwaway container, displaying it on your host via X11. (On Windows, run this from a WSL2 shell with an X server such as the one bundled in recent WSLg, or [VcXsrv](https://sourceforge.net/projects/vcxsrv/), running on the Windows side.)

   On the **Select Product to Install** page, select **Vivado**, then **Vivado ML Standard** under Select Edition. On the components page, uncheck everything, then re-check:
   - **DocNav** (optional, for in-app documentation)
   - Under **Devices -> Production Devices -> SoCs**, check **Zynq-7000** (it's fine that it says "limited support")

   Accept the license agreements, leave the destination directory as the default (`/tools/Xilinx/`, creating a `Vivado/2024.2` folder inside the volume), and click Install.

2. Install PetaLinux, into the separate `petalinux-tools` volume:

   ```bash
   ./scripts/docker/install-petalinux.sh /path/to/FPGAs_AdaptiveSoCs_Unified_2024.2.bin
   ```

   Same installer, same throwaway-container pattern. On the **Select Product to Install** page, scroll to the bottom and select **PetaLinux**, then **PetaLinux arm** under Select Edition, accept the license agreements, and leave the destination directory as the default (again `/tools/Xilinx/`, this time creating a `PetaLinux/2024.2` folder inside the *other* volume).

You can confirm the contents of either volume any time with:

```bash
docker run --rm -v vivado-tools:/tools ubuntu:20.04 ls -la /tools
docker run --rm -v petalinux-tools:/tools ubuntu:20.04 ls -la /tools
```

You won't need to touch these volumes again unless you're installing a different tools version, and you never need to re-run the installers just because you rebuilt or removed a runner container -- the volumes are independent of any container.

## Optional: cocotb and Verilator

Nothing to install separately -- both are baked into the `cocotb` image at build time (see [Building the runner images](#building-the-runner-images) above). Verilator is built from source during the image build, pinned to a tag via the `VERILATOR_REF` build arg in `scripts/docker/cocotb.Dockerfile` (defaults to `stable`). To bump the Verilator version, edit that arg and rebuild:

```bash
docker compose -f scripts/docker/docker-compose.yml build --build-arg VERILATOR_REF=v5.036 cocotb
```

## Optional: PetaLinux offline build setup

The PetaLinux build process requires downloading a lot of files from the internet, which can be slow and unreliable. Depending on your network connection, this could add upwards of ten minutes to the build time. If you want a more reliable build process, you can download these files once and reuse them -- the `petalinux` container has network access by default, so this step is entirely optional; skip it if an online build works fine for you.

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

Mount the two directories into the `petalinux` container read-only, and pass their paths as env vars, overriding the compose-managed container with a one-off `docker run` (the compose service definition doesn't include these bind mounts, since the paths are host-specific):

```bash
docker run -it --rm \
  -v petalinux-tools:/tools/PetaLinux:ro \
  -v "$(pwd):/workspace/zynq_toolbox" \
  -v ~/petalinux_downloads/downloads_2024.2_11061705/downloads:/workspace/petalinux_downloads:ro \
  -v ~/petalinux_downloads/sstate-cache_2024.2_11061705/arm:/workspace/petalinux_sstate:ro \
  -e PETALINUX_DOWNLOADS_PATH=/workspace/petalinux_downloads \
  -e PETALINUX_SSTATE_PATH=/workspace/petalinux_sstate \
  zynq-toolbox-petalinux:2024.2
```

If you want the offline cache available automatically every time the `Makefile` drives the `petalinux` container (i.e. under `MODE=container`, without a manual `docker run`), add the same two bind mounts and env vars to the `petalinux` service in `scripts/docker/docker-compose.yml`, then set `OFFLINE=true` in `make_defaults.mk` or on the command line. That's the only piece of this offline setup that's genuinely host-specific -- everything else in this repo works the same for everyone.

## Running builds

There are two ways to use the containers day to day:

### Driven by the Makefile (recommended)

Set `MODE=container` in `make_defaults.mk` (copy it from `make_defaults.mk.example` if you haven't already):

```make
MODE ?= container
```

Then just run `make` targets from your host exactly as you would with a native VM install -- `make bit`, `make sd`, `make tests`, etc. The Makefile transparently runs the Vivado steps in the `vivado` container, the PetaLinux steps in the `petalinux` container, and cocotb/Verilator tests in the `cocotb` container, using `docker compose -f scripts/docker/docker-compose.yml run` under the hood. Your host itself only needs `make`, `bash`, and Docker -- no Vivado, no PetaLinux, no cocotb.

`MODE` can also be overridden per-invocation without touching `make_defaults.mk`:

```bash
make bit MODE=container
```

`write_sd` always runs directly on the host regardless of `MODE`, since it needs access to a real block device or mount point that a container can't reasonably reach.

### Interactive, for debugging

To get a shell inside a given tool's container -- useful for poking around, checking `vivado -version`, or debugging a failed build by hand:

```bash
docker compose -f scripts/docker/docker-compose.yml run --rm vivado
docker compose -f scripts/docker/docker-compose.yml run --rm petalinux
docker compose -f scripts/docker/docker-compose.yml run --rm cocotb
```

Each drops you into `/workspace/zynq_toolbox` (the bind-mounted repo) as the non-root `builder` user, with that container's tool already on `PATH` and its environment sourced -- confirm with, e.g.:

```bash
echo $ZYNQ_TOOLBOX $VIVADO_PATH   # inside the vivado container
which vivado
```

```bash
echo $ZYNQ_TOOLBOX $PETALINUX_PATH $PETALINUX_VERSION   # inside the petalinux container
which petalinux-create
```

Because the repo directory is bind-mounted rather than copied into the image, anything a container writes into it (build outputs under `out/` and `tmp/`, generated config files) shows up directly on your host, and nothing is lost when the container exits -- `--rm` just means Docker throws away the *container*, not the mounted data or the tool volumes.

With this done, your Docker install is complete -- continue to [Optional: Makefile variable defaults](#optional-makefile-variable-defaults) or straight to [Building an SD card](#building-an-sd-card).

---
