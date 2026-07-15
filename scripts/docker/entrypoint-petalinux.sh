#!/bin/bash
# Sets up ZYNQ_TOOLBOX, PETALINUX_VERSION, and PETALINUX_PATH, and sources
# settings.sh on every container start.

set -e

TOOLS_ROOT="/tools/PetaLinux"
REPO_ROOT="/workspace/zynq_toolbox"

if [ -d "$REPO_ROOT" ]; then
    export ZYNQ_TOOLBOX="$REPO_ROOT"
else
    echo "WARNING: $REPO_ROOT not found." >&2
    echo "         Mount your zynq_toolbox checkout there, e.g.:" >&2
    echo "         -v \$(pwd):/workspace/zynq_toolbox" >&2
fi

# Auto-detect the installed version from the petalinux-tools volume, unless
# pinned via `docker run -e PETALINUX_VERSION=2024.2 ...`
if [ -z "$PETALINUX_VERSION" ] && [ -d "$TOOLS_ROOT" ]; then
    PETALINUX_VERSION="$(ls "$TOOLS_ROOT" 2>/dev/null | sort -V | tail -n1)"
fi

if [ -n "$PETALINUX_VERSION" ]; then
    export PETALINUX_VERSION
    export PETALINUX_PATH="$TOOLS_ROOT/$PETALINUX_VERSION/tool"
else
    echo "WARNING: no PetaLinux install found under $TOOLS_ROOT." >&2
    echo "         Mount your petalinux-tools volume there, e.g.:" >&2
    echo "         -v petalinux-tools:/tools/PetaLinux"  >&2
fi

if [ -f "$PETALINUX_PATH/settings.sh" ]; then
    source "$PETALINUX_PATH/settings.sh"
else
    echo "WARNING: PetaLinux settings.sh not found at $PETALINUX_PATH" >&2
fi

# ---- Optional: offline build cache -----------------------------------------
# For offline builds, mount the extracted cache directories and pass their
# paths at `docker run` time, e.g.:
#   -v /host/path/to/downloads:/workspace/petalinux_downloads:ro \
#   -v /host/path/to/sstate/arm:/workspace/petalinux_sstate:ro \
#   -e PETALINUX_DOWNLOADS_PATH=/workspace/petalinux_downloads \
#   -e PETALINUX_SSTATE_PATH=/workspace/petalinux_sstate
# Omit those two -e flags entirely for an online build -- this container has
# network access by default (unlike the Vivado runner), so OFFLINE=false
# works out of the box.

exec "$@"
