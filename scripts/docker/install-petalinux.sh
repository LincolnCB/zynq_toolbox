#!/bin/bash
# One-time helper: runs the AMD/Xilinx unified installer GUI to write
# PetaLinux into the `petalinux-tools` Docker volume (separate from
# `vivado-tools` -- see install-vivado.sh for the other product). Uses the
# same installer .bin as Vivado.
#
# This uses the *same* image as actual builds (built from
# petalinux.Dockerfile, tagged by docker-compose.yml) -- there is no
# separate throwaway installer image. Two overrides are needed only for
# this one-off install:
#   --user root      a fresh named volume is root-owned, and the image
#                     normally runs as the unprivileged `builder` user
#   --entrypoint bash skips entrypoint-petalinux.sh, which has nothing
#                     useful to do yet (no PetaLinux installed, no version
#                     to detect) and would otherwise just print warnings
#
# In the installer, choose:
#   PetaLinux (scroll to the bottom) -> PetaLinux arm under Select Edition
#   -> accept the license agreements -> leave the destination as the
#      default (/tools/Xilinx/)
#      The whole /tools/Xilinx tree is mounted (as /tools/Xilinx) inside the
#      petalinux-runner container, both here and at runtime, so nothing
#      installed alongside Vivado gets silently dropped.
#
# Usage:
#   ./install-petalinux.sh /path/to/FPGAs_AdaptiveSoCs_Unified_2024.2_*.bin

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

INSTALLER_BIN="$1"
if [ -z "$INSTALLER_BIN" ] || [ ! -f "$INSTALLER_BIN" ]; then
    echo "Usage: $0 /path/to/FPGAs_AdaptiveSoCs_Unified_*.bin" >&2
    exit 1
fi

# Match the UID/GID the petalinux image gets built with, so files the
# installer writes end up owned by you rather than root. If you also set
# these when building/running images for actual builds, keep them
# consistent with that -- otherwise this just defaults to your own user.
export BUILD_UID="${BUILD_UID:-$(id -u)}"
export BUILD_GID="${BUILD_GID:-$(id -g)}"

docker volume create petalinux-tools >/dev/null

# Build (or rebuild, if the Dockerfile changed) the same image the
# petalinux service in docker-compose.yml uses, then resolve its exact tag
# rather than hardcoding "zynq-toolbox-petalinux:2024.2" a second time here.
docker compose -f "$COMPOSE_FILE" build petalinux
PETALINUX_IMAGE="$(docker compose -f "$COMPOSE_FILE" config --images petalinux)"

if [ "$(uname)" = "Linux" ]; then
    xhost +local:docker >/dev/null
fi

docker run -it --rm \
    --user root \
    --entrypoint bash \
    -e DISPLAY="$DISPLAY" \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v petalinux-tools:/tools/Xilinx \
    -v "$(realpath "$INSTALLER_BIN")":/tmp/installer.bin \
    "$PETALINUX_IMAGE" \
    -c "chmod +x /tmp/installer.bin && /tmp/installer.bin && chown -R ${BUILD_UID}:${BUILD_GID} /tools/Xilinx"

if [ "$(uname)" = "Linux" ]; then
    xhost -local:docker >/dev/null
fi


# Sanity-check that everything we expect the installer to have written
# actually landed in the volume. Each of these is checked independently so
# a missing one is reported by name instead of just failing at the first
# check -- e.g. if you forgot to re-check Vitis/Vitis HLS in the component
# picker, this tells you exactly that, instead of failing opaquely later
# on inside a build container.
MISSING=()
for product in PetaLinux; do
    if ! docker run --rm --entrypoint bash \
        -v vivado-tools:/tools/Xilinx "$PETALINUX_IMAGE" \
        -c "[ -d /tools/Xilinx/${product} ]" \
        >/dev/null 2>&1; then
        MISSING+=("$product")
    fi
done

if [ "${#MISSING[@]}" -gt 0 ]; then
    echo ""
    echo "WARNING: install finished, but the following expected directories" >&2
    echo "are missing from the 'petalinux-tools' volume under /tools/Xilinx:" >&2
    for product in "${MISSING[@]}"; do
        echo "  - $product" >&2
    done
    echo "" >&2
fi

echo ""
echo "Installer closed. The 'petalinux-tools' volume now contains PetaLinux"
echo "under /tools/Xilinx/PetaLinux/<version> (mounted as /tools/PetaLinux"
echo "at runtime). Optional next step: petalinux-sstate-install.sh for the"
echo "offline build cache -- see docker_install.md."
