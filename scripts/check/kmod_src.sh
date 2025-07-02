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

# Check for the kernel_modules file
KERNEL_MODULES_FILE="projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/kernel_modules"
if [ -f "${KERNEL_MODULES_FILE}" ]; then
  while IFS= read -r module || [ -n "$module" ]; do
    # Ensure each line is a single word
    if [[ ! "$module" =~ ^[a-z0-9-]+$ ]]; then
      echo "[CHECK KERNEL MODULES] ERROR:"
      echo "Invalid module name '${module}' in ${KERNEL_MODULES_FILE}"
      echo "Each line must contain only one valid word in kebab-case (lowercase alphanumeric and hyphens)."
      exit 1
    fi

    # Check if the directory for the module exists
    if [ ! -d "kernel_modules/${module}" ]; then
      echo "[CHECK KERNEL MODULES] ERROR:"
      echo "Kernel module directory not found for '${module}'"
      echo "Expected path: kernel_modules/${module}"
      exit 1
    fi

    # Check that the directory for the module contains a PetaLinux folder of the correct version
    if [ ! -d "kernel_modules/${module}/petalinux/${PETALINUX_VERSION}" ]; then
      echo "[CHECK KERNEL MODULES] ERROR:"
      echo "Missing PetaLinux version ${PETALINUX_VERSION} folder for '${module}'"
      echo "Expected path: kernel_modules/${module}/petalinux/${PETALINUX_VERSION}"
      exit 1
    fi

    # Check that the PetaLinux folder contains a Makefile and C file of the same name
    if [ ! -f "kernel_modules/${module}/petalinux/${PETALINUX_VERSION}/Makefile" ]; then
      echo "[CHECK KERNEL MODULES] ERROR:"
      echo "Missing PetaLinux-configured Makefile for '${module}'"
      echo "Expected path: kernel_modules/${module}/petalinux/${PETALINUX_VERSION}/Makefile"
      exit 1
    fi
    if [ ! -f "kernel_modules/${module}/petalinux/${PETALINUX_VERSION}/${module}.c" ]; then
      echo "[CHECK KERNEL MODULES] ERROR:"
      echo "Missing kernel module C file for '${module}'"
      echo "Expected path: kernel_modules/${module}/petalinux/${PETALINUX_VERSION}/${module}.c"
      exit 1
    fi
  done <"${KERNEL_MODULES_FILE}"
fi
