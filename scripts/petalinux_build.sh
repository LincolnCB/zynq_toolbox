#!/bin/bash
# Build a PetaLinux project for the given board and project
# Usage: petalinux.sh <board_name> <project_name>
if [ $# -ne 2 ]; then
    echo "Usage: $0 <board_name> <project_name>"
    exit 1
fi

# Store the positional parameters in named variables and clear them
BRD=${1}
PRJ=${2}
set --

# Check that the necessary XSA exists
if [ ! -f "tmp/${BRD}/${PRJ}/hw_def.xsa" ]; then
    echo "Missing generated XSA hardware definition file: tmp/${BRD}/${PRJ}/hw_def.xsa."
    echo "First run the following command:"
    echo
    echo "  make BOARD=${BRD} PROJECT=${PRJ} xsa"
    echo
    exit 1
fi

# Check that the necessary PetaLinux config files exist
if [ ! -f "projects/${PRJ}/petalinux_cfg/config.patch" ]; then
    echo "Missing PetaLinux project configuration patch file for project ${PRJ}: projects/${PRJ}/petalinux_cfg/config.patch"
    echo "You can create this file by running the following command:"
    echo
    echo "  scripts/petalinux_config_project.sh ${BRD} ${PRJ}"
    echo
    exit 1
fi
if [ ! -f "projects/${PRJ}/petalinux_cfg/rootfs_config.patch" ]; then
    echo "Missing PetaLinux filesystem configuration patch file for project ${PRJ}: projects/${PRJ}/petalinux_cfg/rootfs_config.patch"
    echo "You can create this file by running the following command:"
    echo
    echo "  scripts/petalinux_config_rootfs.sh ${BRD} ${PRJ}"
    echo
    exit 1
fi

# Create and enter the project
cd tmp/${BRD}/${PRJ}
petalinux-create -t project --template zynq --name petalinux --force
cd petalinux

# Patch the project configuration
echo "[MAKE SCRIPT] Initializing default project configuration"
petalinux-config --get-hw-description ../hw_def.xsa --silentconfig
echo "[MAKE SCRIPT] Patching and configuring project"
patch project-spec/configs/config ../../../../projects/${PRJ}/petalinux_cfg/config.patch
petalinux-config --silentconfig

# Patch the root filesystem configuration
echo "[MAKE SCRIPT] Initializing default root filesystem configuration"
petalinux-config -c rootfs --silentconfig
echo "[MAKE SCRIPT] Patching and configuring root filesystem"
patch project-spec/configs/rootfs_config ../../../../projects/${PRJ}/petalinux_cfg/rootfs_config.patch
petalinux-config -c rootfs --silentconfig

# Build the project
echo "[MAKE SCRIPT] Building the project"
petalinux-build
