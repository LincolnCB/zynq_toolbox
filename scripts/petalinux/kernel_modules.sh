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

# Check that the minimum kernel module requirements are met
./scripts/check/kmod_src.sh ${BRD} ${VER} ${PRJ}

# Check for a kernel_modules file
KERNEL_MODULES_FILE="projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/kernel_modules"
if [ ! -f "${KERNEL_MODULES_FILE}" ]; then
  echo "[PTLNX KMODS] INFO: No kernel_modules file found. Skipping kernel module checks."
  echo "  Path: ${KERNEL_MODULES_FILE}"
  exit 0
fi

# Source the PetaLinux settings script (make sure to clear positional parameters first)
source ${PETALINUX_PATH}/settings.sh

# Enter the PetaLinux project directory
cd tmp/${BRD}/${VER}/${PRJ}/petalinux

# Add kernel modules to the project
echo "[PTLNX KMODS] Adding kernel modules to PetaLinux project"
while IFS= read -r MOD; do
  echo "[PTLNX KMODS] Adding kernel module: ${MOD}"
  petalinux-create modules --name ${MOD} --enable --force

  # Copy the source files into the kernel module directory
  SRC_DIR="../../../../../kernel_modules/${MOD}/petalinux/${PETALINUX_VERSION}"
  KMOD_DIR="project-spec/meta-user/recipes-modules/${MOD}/files"

  # Copy the makefile and top source file, overwriting the default ones
  cp -f "${SRC_DIR}/Makefile" "${KMOD_DIR}/Makefile"
  cp -f "${SRC_DIR}/${MOD}.c" "${KMOD_DIR}/${MOD}.c"

  # Copy any additional source files, excluding those two
  find "${SRC_DIR}" -type f ! -name "Makefile" ! -name "${MOD}.c" -exec cp -f {} "${KMOD_DIR}/" \;

done < ../../../../../${KERNEL_MODULES_FILE}


