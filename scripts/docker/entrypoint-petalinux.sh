#!/bin/bash
# Sets up ZYNQ_TOOLBOX, PETALINUX_VERSION, and PETALINUX_PATH, and sources
# settings.sh on every container start.

set -e

TOOLS_ROOT="/tools/Xilinx/PetaLinux"
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
    echo "         Mount your petalinux-tools volume at /tools/Xilinx, e.g.:" >&2
    echo "         -v petalinux-tools:/tools/Xilinx"  >&2
fi

if [ -f "$PETALINUX_PATH/settings.sh" ]; then
    source "$PETALINUX_PATH/settings.sh"
else
    echo "WARNING: PetaLinux settings.sh not found at $PETALINUX_PATH" >&2
fi

exec "$@"
