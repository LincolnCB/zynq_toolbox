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
./scripts/check/project_dir.sh ${BRD} ${VER} ${PRJ}
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
SW_PATH="${REV_D_DIR}/projects/${PRJ}/software"

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

    # Get a list of .c and .h files that aren't the top file
    C_FILES=$(find "${SW_DIR}" -type f -name "*.c" ! -name "${SW_NAME}.c")
    H_FILES=$(find "${SW_DIR}" -type f -name "*.h")
    SRC_FILES=""
    if [ -n "${C_FILES}" ]; then
      SRC_FILES+=" ${C_FILES}"
    fi
    if [ -n "${H_FILES}" ]; then
      SRC_FILES+=" ${H_FILES}"
    fi
    if [ -z "${SRC_FILES}" ]; then
      petalinux-create apps --template c --name ${SAN_SW_NAME} --enable
    else
      petalinux-create apps --template c --name ${SAN_SW_NAME} --srcuri "${SRC_FILES}" --enable
      # Update SRC_URI in the .bb file to include Makefile and top .c file
      BBFILE="project-spec/meta-user/recipes-apps/${SAN_SW_NAME}/${SAN_SW_NAME}.bb"
      sed -i "s|^SRC_URI *= *\"|SRC_URI = \"file://Makefile file://${SAN_SW_NAME}.c |" "${BBFILE}"
    fi

    # Copy the top file to the app directory and replace the existing one
    cp "${SW_DIR}/${SW_NAME}.c" "project-spec/meta-user/recipes-apps/${SAN_SW_NAME}/files/${SAN_SW_NAME}.c"

    # Update the Makefile to include all object files
    MAKEFILE="project-spec/meta-user/recipes-apps/${SAN_SW_NAME}/files/Makefile"
    if [ -f "${MAKEFILE}" ]; then
      # Build the list of object files: all .c files (basename, .c -> .o)
      OBJ_FILES="${SAN_SW_NAME}.o"
      for SRC in ${C_FILES}; do
      OBJ_NAME=$(basename "${SRC}" .c).o
      OBJ_FILES="${OBJ_FILES} ${OBJ_NAME}"
      done
      # Remove leading space
      OBJ_FILES=$(echo "${OBJ_FILES}" | sed 's/^ *//')
      # Replace the APP_OBJS line
      sed -i "s|^APP_OBJS *=.*$|APP_OBJS = ${OBJ_FILES}|" "${MAKEFILE}"
    fi
  fi

  if [ ${ANY_SW} -eq 0 ]; then
    echo "[PTLNX SOFTWARE] No software directories to build for ${PBV}"
    echo " Path: ${SW_PATH}"
    exit 0
  fi
done
