#!/bin/bash
# Build a PetaLinux project for the given board name
# Usage: petalinux.sh <board_name> <project_name>
if [ $# -ne 2 ]; then
    echo "Usage: $0 <board_name> <project_name>"
    exit 1
fi

# Check that the necessary XSA exists
if [ ! -f "tmp/${1}_${2}.xsa" ]; then
    echo "Missing generated XSA hardware definition file: tmp/${1}_${2}.xsa."
    exit 1
fi

# Check that the necessary PetaLinux config files exist
if [ ! -f "projects/${2}/petalinux_cfg/config" ]; then
    echo "Missing source PetaLinux project configuration for project ${2}: projects/${2}/petalinux_cfg/config"
    exit 1
fi
if [ ! -f "projects/${2}/petalinux_cfg/config" ]; then
    echo "Missing source filesystem project configuration for project ${2}: projects/${2}/petalinux_cfg/rootfs_config"
    exit 1
fi

# Make the project
cd tmp
echo "[MAKE SCRIPT] Creating project"
petalinux-create project --template zynq --name ${1}_${2}_petalinux

# Copy the configuration files into the project
echo "[MAKE SCRIPT] Copying configuration files"
cp ../projects/${2}/petalinux_cfg/config ${1}_${2}_petalinux/project-spec/configs
cp ../projects/${2}/petalinux_cfg/rootfs_config ${1}_${2}_petalinux/project-spec/configs

# Enter the project
cd ${1}_${2}_petalinux

# Configure the project and add the XSA file
echo "[MAKE SCRIPT] Configuring project"
petalinux-config --get-hw-description ../${1}_${2}.xsa --silentconfig

# Configure the root filesystem
echo "[MAKE SCRIPT] Configuring root filesystem"
petalinux-config -c rootfs --silentconfig


# Build the project
echo "[MAKE SCRIPT] Building the project"
petalinux-build
