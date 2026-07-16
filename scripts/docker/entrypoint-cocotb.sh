#!/bin/bash
# cocotb and Verilator are baked into this image, so there's no tools volume
# to detect -- just set ZYNQ_TOOLBOX and hand off.

set -e

REPO_ROOT="/workspace/zynq_toolbox"

if [ -d "$REPO_ROOT" ]; then
    export ZYNQ_TOOLBOX="$REPO_ROOT"
else
    echo "WARNING: $REPO_ROOT not found." >&2
    echo "         Mount your zynq_toolbox checkout there, e.g.:" >&2
    echo "         -v \$(pwd):/workspace/zynq_toolbox" >&2
fi

export PATH="$HOME/.local/bin:$PATH"

exec "$@"
