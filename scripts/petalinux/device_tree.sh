#!/bin/bash
# Copy the PetaLinux user device tree additions for the given board and project
# Arguments: <board_name> <board_version> <project_name>
if [ $# -ne 3 ]; then
  echo "[PTLNX DEVICE TREE] ERROR:"
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

# Check that the PetaLinux project and its dependencies exist
./scripts/check/project_dir.sh ${BRD} ${VER} ${PRJ}
./scripts/check/petalinux_project.sh ${BRD} ${VER} ${PRJ}

REL_DEVICE_TREE_PATH="projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/device_tree.dtsi"

# Check for the device tree file, end if it does not exist
if [ ! -d "projects/${PRJ}/software" ]; then
  echo "[PTLNX DEVICE TREE] No device tree to include for PetaLinux version ${PETALINUX_VERSION} of ${PBV}"
  echo " Path: ${REL_DEVICE_TREE_PATH}"
  exit 0
fi

# Enter the PetaLinux project directory
cd tmp/${BRD}/${VER}/${PRJ}/petalinux

# Copy the device tree file to the PetaLinux project
echo "[PTLNX DEVICE TREE] Copying device tree file to PetaLinux project"
cp -f "${REV_D_DIR}/${REL_DEVICE_TREE_PATH}" "project-spec/meta-user/recipes-bsp/device-tree/files/system-user.dtsi"
  
