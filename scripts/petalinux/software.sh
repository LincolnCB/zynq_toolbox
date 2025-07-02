#!/bin/bash
# Build PetaLinux software for the given board and project
# Arguments: <board_name> <board_version> <project_name>
if [ $# -ne 3 ]; then
  echo "[PTLNX SOFTWARE] ERROR:"
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
./scripts/check/petalinux_project.sh ${BRD} ${VER} ${PRJ}

# Check for a software folder
if [ ! -d "projects/${PRJ}/software" ]; then
  echo "[PTLNX SOFTWARE] No software directories to build for ${PBV}"
  echo " Path: projects/${PRJ}/software"
  exit 0
fi

# Source the PetaLinux settings script (make sure to clear positional parameters first)
source ${PETALINUX_PATH}/settings.sh

# Enter the project
cd tmp/${BRD}/${VER}/${PRJ}/petalinux

# Set the software path
SW_PATH="../../../../../projects/${PRJ}/software"

# For each software folder, build the software
echo "[PTLNX SOFTWARE] Building software for ${PBV}"
for SW_DIR in ${SW_PATH}/*; do

  # Check if there were any software directories
  ANY_SW=0

  # Check if the directory is a software directory
  if [ -d "${SW_DIR}" ]; then
    ANY_SW=1
    SW_NAME=$(basename "${SW_DIR}")

    # Require a top file of the same name as the directory
    if [ ! -f "${SW_DIR}/${SW_NAME}.c" ]; then
      echo "[PTLNX SOFTWARE] ERROR:"
      echo "${SW_NAME} directory missing top file ${SW_NAME}.c"
      echo "Please create the top file and re-run the build."
      echo " Path: projects/${PRJ}/software/${SW_NAME}/${SW_NAME}.c"
      exit 1
      continue
    fi

    # Sanitize the software name
    SAN_SW_NAME=$(echo "${SW_NAME}" | tr '[:upper:]' '[:lower:]' | tr '_ ' '-')
    if [ "${SAN_SW_NAME}" != "${SW_NAME}" ]; then
      echo "[PTLNX SOFTWARE] WARNING: Software name sanitized from '${SW_NAME}' to '${SAN_SW_NAME}'"
    fi

    # Remove any existing app directory in the PetaLinux project
    if [ -d "project-spec/meta-user/recipes-apps/${SAN_SW_NAME}" ]; then
      echo "[PTLNX SOFTWARE] Removing existing directory: project-spec/meta-user/recipes-apps/${SAN_SW_NAME}"
      rm -rf "project-spec/meta-user/recipes-apps/${SAN_SW_NAME}"
    fi

    # Create the app directory and copy the source files in
    echo "[PTLNX SOFTWARE] Building ${SAN_SW_NAME}"

    # Get a list of .c files that aren't the top file
    SRC_FILES=$(find "${SW_DIR}" -type f -name "*.c" ! -name "${SW_NAME}.c")
    if [ -z "${SRC_FILES}" ]; then
      petalinux-create apps --template c --name ${SAN_SW_NAME} --enable
    else
      petalinux-create apps --template c --name ${SAN_SW_NAME} --srcuri "${SRC_FILES}" --enable
    fi

    # Copy the top file to the app directory and replace the existing one
    cp "${SW_DIR}/${SW_NAME}.c" "project-spec/meta-user/recipes-apps/${SAN_SW_NAME}/files/${SAN_SW_NAME}.c"
  fi

  if [ ${ANY_SW} -eq 0 ]; then
    echo "[PTLNX SOFTWARE] No software directories to build for ${PBV}"
    echo " Path: ${SW_PATH}"
    exit 0
  fi
done
