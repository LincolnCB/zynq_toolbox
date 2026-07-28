#!/bin/bash
# Check the kernel modules for a project, board, and version
# Arguments: <board_name> <board_version> <project_name> [--full]
# Full check: PetaLinux project and prerequisites
# Minimum check: Project source and PetaLinux project (PetaLinux project check includes PetaLinux environment check)

# Parse arguments
FULL_CHECK=false

# Loop through arguments to find --full and assign positional parameters
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--full" ]]; then
    FULL_CHECK=true
  else
    ARGS+=("$arg")
  fi
done

# There must be exactly 3 positional arguments (board, version, project)
if [ "${#ARGS[@]}" -ne 3 ]; then
  echo "[CHECK KERNEL MODULES] ERROR:"
  echo "Usage: $0 <board_name> <board_version> <project_name> [--full]"
  exit 1
fi

BRD="${ARGS[0]}"
VER="${ARGS[1]}"
PRJ="${ARGS[2]}"
PBV="project \"${PRJ}\" and board \"${BRD}\" v${VER}"
set --

# If any subsequent command fails, exit immediately
set -e

# Check prerequisites. If full, check all prerequisites. Otherwise, just the immediate necessary ones.
if $FULL_CHECK; then
  # Full check: PetaLinux project and prerequisites
  ./scripts/check/petalinux_project.sh ${BRD} ${VER} ${PRJ} --full
else
  # Minimum check: Project directory and PetaLinux project (includes PetaLinux environment check)
  ./scripts/check/project_dir.sh ${BRD} ${VER} ${PRJ}
  ./scripts/check/petalinux_project.sh ${BRD} ${VER} ${PRJ} # Includes PetaLinux environment check
fi

# Check the kernel_modules folder, if it exists
KMOD_DIR="projects/${PRJ}/kernel_modules"
if [ -d "${KMOD_DIR}" ]; then
  for MOD_DIR in "${KMOD_DIR}"/*; do

    # Skip anything that isn't a directory. The -d test follows symlinks, so
    # modules symlinked in from examples/kernel_modules/ are checked normally.
    [ -d "${MOD_DIR}" ] || continue
    module=$(basename "${MOD_DIR}")

    # The directory name becomes a Yocto recipe name, so it must be kebab-case
    if [[ ! "$module" =~ ^[a-z0-9-]+$ ]]; then
      echo "[CHECK KERNEL MODULES] ERROR:"
      echo "Invalid kernel module directory name '${module}'"
      echo "Expected path: ${KMOD_DIR}/${module}"
      echo "Directory names must be kebab-case (lowercase alphanumeric and hyphens)."
      exit 1
    fi

    # Check that the directory contains a PetaLinux folder
    if [ ! -d "${MOD_DIR}/petalinux" ]; then
      echo "[CHECK KERNEL MODULES] ERROR:"
      echo "Missing PetaLinux folder for '${module}'"
      echo "Expected path: ${KMOD_DIR}/${module}/petalinux"
      exit 1
    fi

    # Check that the PetaLinux folder contains a Makefile and C file of the same name
    if [ ! -f "${MOD_DIR}/petalinux/Makefile" ]; then
      echo "[CHECK KERNEL MODULES] ERROR:"
      echo "Missing PetaLinux-configured Makefile for '${module}'"
      echo "Expected path: ${KMOD_DIR}/${module}/petalinux/Makefile"
      exit 1
    fi
    if [ ! -f "${MOD_DIR}/petalinux/${module}.c" ]; then
      echo "[CHECK KERNEL MODULES] ERROR:"
      echo "Missing kernel module C file for '${module}'"
      echo "Expected path: ${KMOD_DIR}/${module}/petalinux/${module}.c"
      exit 1
    fi
  done
fi
