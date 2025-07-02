#!/bin/bash
# Build a PetaLinux project for the given board and project
# Arguments: <board_name> <board_version> <project_name>
if [ $# -ne 3 ]; then
  echo "[PTLNX PROJECT] ERROR:"
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

# Check the PetaLinux project prerequisites: XSA file and configuration files
echo "[PTLNX PROJECT] Checking PetaLinux configuration files for ${PBV}"
./scripts/check/xsa_file.sh ${BRD} ${VER} ${PRJ} || exit 1
./scripts/check/petalinux_rootfs_cfg_file.sh ${BRD} ${VER} ${PRJ} || exit 1

# Delete any existing project directory
echo "[PTLNX PROJECT] Deleting any existing PetaLinux project directory"
rm -rf tmp/${BRD}/${VER}/${PRJ}/petalinux

# Extract the PetaLinux year from the version string
if [[ "$PETALINUX_VERSION" =~ ^([0-9]{4}) ]]; then
  PETALINUX_YEAR=${BASH_REMATCH[1]}
else
  echo "[PTLNX PROJECT] ERROR: Invalid PetaLinux version format (${PETALINUX_VERSION}). Expected format: YYYY.X"
  exit 1
fi

# Source the PetaLinux settings script (make sure to clear positional parameters first)
source ${PETALINUX_PATH}/settings.sh

# Create and enter the project
cd tmp/${BRD}/${VER}/${PRJ}
if [ "$PETALINUX_YEAR" -lt 2024 ]; then
  echo "[PTLNX PROJECT] Using legacy PetaLinux project creation command for year ${PETALINUX_YEAR}"
  petalinux-create -t project --template zynq --name petalinux --force
else
  echo "[PTLNX PROJECT] Using PetaLinux project creation python arguments (for year ${PETALINUX_YEAR})"
  petalinux-create project --template zynq --name petalinux --force
fi
cd petalinux

# Initialize the project with the hardware description
echo "[PTLNX PROJECT] Initializing default PetaLinux system configuration"
petalinux-config --get-hw-description ../hw_def.xsa --silentconfig

# Check that the PetaLinux version matches the environment variable
PETALINUX_CONF_PATH="components/yocto/layers/meta-petalinux/conf/distro/include/petalinux-version.conf"
if [ -f "$PETALINUX_CONF_PATH" ]; then
  CONF_XILINX_VER_MAIN=$(grep -oP '(?<=XILINX_VER_MAIN = ")[^"]+' "$PETALINUX_CONF_PATH")
  if [ "$PETALINUX_VERSION" != "$CONF_XILINX_VER_MAIN" ]; then
    echo "[PTLNX PROJECT] ERROR: PETALINUX_VERSION (${PETALINUX_VERSION}) does not match XILINX_VER_MAIN (${CONF_XILINX_VER_MAIN}) in petalinux-version.conf. This likely means you have the wrong or missing PETALINUX_VERSION environment variable set."
    exit 1
  fi
else
  echo "[PTLNX PROJECT] ERROR: petalinux-version.conf not found at $PETALINUX_CONF_PATH"
  exit 1
fi

# Patch the project configuration
echo "[PTLNX PROJECT] Patching and configuring PetaLinux project"
patch project-spec/configs/config ../../../../../projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/config.patch
petalinux-config --silentconfig

# Patch the root filesystem configuration
echo "[PTLNX PROJECT] Initializing default PetaLinux root filesystem configuration"
petalinux-config -c rootfs --silentconfig
echo "[PTLNX PROJECT] Patching and configuring PetaLinux root filesystem"
patch project-spec/configs/rootfs_config ../../../../../projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/rootfs_config.patch
petalinux-config -c rootfs --silentconfig
