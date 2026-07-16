#!/bin/bash
# One-time helper: runs the AMD/Xilinx unified installer GUI to write Vivado
# into the `vivado-tools` Docker volume (separate from `petalinux-tools` --
# see install-petalinux.sh for the other product).
#
# This uses the *same* image as actual builds (built from vivado.Dockerfile,
# tagged by docker-compose.yml) -- there is no separate throwaway installer
# image. Two overrides are needed only for this one-off install:
#   --user root      a fresh named volume is root-owned, and the image
#                     normally runs as the unprivileged `builder` user
#   --entrypoint bash skips entrypoint-vivado.sh, which has nothing useful
#                     to do yet (no Vivado installed, no version to detect)
#                     and would otherwise just print warnings
#
# In the installer, choose:
#   Vivado -> Vivado ML Standard -> uncheck all components, then re-check
#   DocNav (optional) and Devices > Production Devices > SoCs > Zynq-7000
#   -> leave the destination as the default (/tools/Xilinx/), which lands
#      as /tools/Xilinx/Vivado/<version> and gets mounted at /tools/Vivado
#      inside the vivado-runner container.
#
# Usage:
#   ./install-vivado.sh /path/to/FPGAs_AdaptiveSoCs_Unified_2024.2_*.bin

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

INSTALLER_BIN="$1"
if [ -z "$INSTALLER_BIN" ] || [ ! -f "$INSTALLER_BIN" ]; then
    echo "Usage: $0 /path/to/FPGAs_AdaptiveSoCs_Unified_*.bin" >&2
    exit 1
fi

# Match the UID/GID the vivado image gets built with, so files the
# installer writes end up owned by you rather than root. If you also set
# these when building/running images for actual builds, keep them
# consistent with that -- otherwise this just defaults to your own user.
export BUILD_UID="${BUILD_UID:-$(id -u)}"
export BUILD_GID="${BUILD_GID:-$(id -g)}"

docker volume create vivado-tools >/dev/null

# Build (or rebuild, if the Dockerfile changed) the same image the vivado
# service in docker-compose.yml uses, then resolve its exact tag rather
# than hardcoding "zynq-toolbox-vivado:2024.2" a second time here.
docker compose -f "$COMPOSE_FILE" build vivado
VIVADO_IMAGE="$(docker compose -f "$COMPOSE_FILE" config --images vivado)"

if [ "$(uname)" = "Linux" ]; then
    xhost +local:docker >/dev/null
fi

docker run -it --rm \
    --user root \
    --entrypoint bash \
    -e DISPLAY="$DISPLAY" \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v vivado-tools:/tools/Xilinx/Vivado \
    -v "$(realpath "$INSTALLER_BIN")":/tmp/installer.bin \
    "$VIVADO_IMAGE" \
    -c "chmod +x /tmp/installer.bin && /tmp/installer.bin && chown -R ${BUILD_UID}:${BUILD_GID} /tools/Xilinx/Vivado"

if [ "$(uname)" = "Linux" ]; then
    xhost -local:docker >/dev/null
fi

echo ""
echo "Installer closed. The 'vivado-tools' volume now contains Vivado under"
echo "/tools/Xilinx/Vivado/<version> (mounted as /tools/Vivado at runtime)."
echo "Run install-petalinux.sh separately -- with the same .bin file -- to"
echo "install PetaLinux into its own 'petalinux-tools' volume."
