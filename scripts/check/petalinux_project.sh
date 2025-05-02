#!/bin/bash
# Check if the XSA for a project exists
# Arguments: <board_name> <board_version> <project_name>
if [ $# -ne 3 ]; then
    echo "[CHECK PTLNX PROJECT] ERROR:"
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

# Check PetaLinux config file
./scripts/check/petalinux_rootfs_cfg.sh ${BRD} ${VER} ${PRJ}

# Check that the necessary PetaLinux project exists
if [ ! -d "tmp/${BRD}/${VER}/${PRJ}/petalinux" ]; then
    echo "[CHECK PTLNX PROJECT] ERROR:"
    echo "Missing PetaLinux project directory for ${PBV}"
    echo " Path: tmp/${BRD}/${VER}/${PRJ}/petalinux."
    echo "First run the following command:"
    echo
    echo " make BOARD=${BRD} BOARD_VER=${VER} PROJECT=${PRJ} petalinux"
    echo
    exit 1
fi
