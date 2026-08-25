#!/bin/bash
# Add out-of-tree kernel modules to the PetaLinux project for the given board and project
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

# Check for a kernel_modules folder
if [ ! -d "projects/${PRJ}/kernel_modules" ]; then
  echo "[PTLNX KMODS] No kernel modules to build for ${PBV}"
  echo " Path: projects/${PRJ}/kernel_modules"
  exit 0
fi

# Source the PetaLinux settings script (make sure to clear positional parameters first)
if [ -z "$PETALINUX" ]; then
  source ${PETALINUX_PATH}/settings.sh
fi

# Set the kernel module path (absolute, because we change directory below)
KMOD_PATH="${ZYNQ_TOOLBOX}/projects/${PRJ}/kernel_modules"

# Enter the PetaLinux project directory
cd tmp/${BRD}/${VER}/${PRJ}/petalinux

# For each module folder, add the module to the project
echo "[PTLNX KMODS] Adding kernel modules to PetaLinux project"
ANY_MOD=0
for MOD_DIR in ${KMOD_PATH}/*; do

  # Skip anything that isn't a directory. The -d test follows symlinks, so
  # modules symlinked in from examples/kernel_modules/ are picked up normally.
  [ -d "${MOD_DIR}" ] || continue
  ANY_MOD=1

  MOD=$(basename "${MOD_DIR}")
  echo "[PTLNX KMODS] Adding kernel module: ${MOD}"
  petalinux-create modules --name ${MOD} --enable --force

  # Copy the source files into the kernel module directory
  SRC_DIR="${MOD_DIR}/petalinux"
  KMOD_DIR="project-spec/meta-user/recipes-modules/${MOD}/files"

  # Copy the makefile and top source file, overwriting the default ones
  cp -f "${SRC_DIR}/Makefile" "${KMOD_DIR}/Makefile"
  cp -f "${SRC_DIR}/${MOD}.c" "${KMOD_DIR}/${MOD}.c"

  # Copy any additional source files, excluding those two
  find -L "${SRC_DIR}" -type f ! -name "Makefile" ! -name "${MOD}.c" -exec cp -f {} "${KMOD_DIR}/" \;

  # The generated recipe lists its sources explicitly in SRC_URI, and only the
  # files named there are unpacked into the build directory. petalinux-create
  # already lists Makefile and ${MOD}.c, so any additional files copied above
  # must be added to SRC_URI or they will never reach the compile.
  EXTRA_FILES=$(find -L "${SRC_DIR}" -type f ! -name "Makefile" ! -name "${MOD}.c" -exec basename {} \;)
  if [ -n "${EXTRA_FILES}" ]; then
    SRC_URI_ADD=""
    for f in ${EXTRA_FILES}; do
      SRC_URI_ADD+="file://${f} "
    done
    BBFILE="project-spec/meta-user/recipes-modules/${MOD}/${MOD}.bb"
    echo "[PTLNX KMODS] Adding to SRC_URI: ${EXTRA_FILES}"
    sed -i "s|^SRC_URI *= *\"|SRC_URI = \"${SRC_URI_ADD}|" "${BBFILE}"
  fi

  # Autoload the module at boot. This writes /etc/modules-load.d/${MOD}.conf
  # into the rootfs so the module comes up automatically -- userspace never has
  # to modprobe it by hand. KERNEL_MODULE_AUTOLOAD is idempotent per name, so
  # appending it once per module is safe.
  BBFILE="project-spec/meta-user/recipes-modules/${MOD}/${MOD}.bb"
  echo "[PTLNX KMODS] Enabling autoload for: ${MOD}"
  echo "KERNEL_MODULE_AUTOLOAD += \"${MOD}\"" >> "${BBFILE}"

done

if [ ${ANY_MOD} -eq 0 ]; then
  echo "[PTLNX KMODS] No kernel modules to build for ${PBV}"
  echo " Path: projects/${PRJ}/kernel_modules"
fi
