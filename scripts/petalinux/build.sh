#!/bin/bash
# Build a PetaLinux project for the given board and project
# Arguments: <board_name> <board_version> <project_name>
if [ $# -ne 3 ]; then
    echo "[PTLNX BUILD SCRIPT] ERROR:"
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

# Check that the necessary PetaLinux config files (and dependencies) exist
./scripts/check/petalinux_rootfs_cfg.sh ${BRD} ${VER} ${PRJ}

# Create and enter the project
cd tmp/${BRD}/${VER}/${PRJ}
petalinux-create -t project --template zynq --name petalinux --force
cd petalinux

# Patch the project configuration
echo "[PTLNX BUILD SCRIPT] Initializing default PetaLinux project configuration"
petalinux-config --get-hw-description ../hw_def.xsa --silentconfig
echo "[PTLNX BUILD SCRIPT] Patching and configuring PetaLinux project"
patch project-spec/configs/config ../../../../../projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/config.patch
petalinux-config --silentconfig

# Patch the root filesystem configuration
echo "[PTLNX BUILD SCRIPT] Initializing default PetaLinux root filesystem configuration"
petalinux-config -c rootfs --silentconfig
echo "[PTLNX BUILD SCRIPT] Patching and configuring PetaLinux root filesystem"
patch project-spec/configs/rootfs_config ../../../../../projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/rootfs_config.patch
petalinux-config -c rootfs --silentconfig

# Build the project
echo "[PTLNX BUILD SCRIPT] Building the PetaLinux project"
petalinux-build
