#!/bin/bash
# Build a PetaLinux project for the given board and project
# Arguments: <board_name> <board_version> <project_name>
if [ $# -ne 3 ]; then
    echo "[PTLNX KMODS] ERROR:"
    echo "Usage: $0 <board_name> <board_version> <project_name>"
    exit 1
fi

# Store the positional parameters in named variables and clear them
BRD=${1}
VER=${2}
PRJ=${3}
PBV="project \"${PRJ}\" and board \"${BRD}\" v${VER}"
set --

# If any subsequent command fails, exit immediately
set -e

# Check that the kernel module requirements are met
./scripts/check/kernel_modules.sh ${BRD} ${VER} ${PRJ}

KERNEL_MODULES_FILE="projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/kernel_modules"
if [ ! -f "${KERNEL_MODULES_FILE}" ]; then
    echo "[PTLNS KMODS] INFO: No kernel_modules file found. Skipping kernel module checks."
    exit 0
fi

# Add kernel modules to the project
# TODO: Not actually adding kernel modules yet, just doing a dummy step
echo "[PTLNX KMODS] Adding kernel modules to PetaLinux project"
if [ -f ../../../../../projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/kernel_modules ]; then
    while IFS= read -r MOD; do
        echo "[PTLNX KMODS] Adding kernel module: ${MOD}"
        petalinux-create modules --name ${MOD} --enable
    done < ../../../../../projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/kernel_modules
else
    echo "[PTLNX KMODS] No kernel_modules file found, skipping kernel module addition"
fi


