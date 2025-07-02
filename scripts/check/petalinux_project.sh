#!/bin/bash
# Check the PetaLinux project for a board and version
# Arguments: <board_name> <board_version> <project_name> [--full]
# Full check: PetaLinux environment and prerequisites
# Minimum check: PetaLinux environment

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

if [ ${#ARGS[@]} -ne 3 ]; then
  echo "[CHECK PTLNX PROJECT] ERROR:"
  echo "Usage: $0 <board_name> <board_version> <project_name> [--full]"
  exit 1
fi

BRD=${ARGS[0]}
VER=${ARGS[1]}
PRJ=${ARGS[2]}
PBV="project \"${PRJ}\" and board \"${BRD}\" v${VER}"
set --

# If any subsequent command fails, exit immediately
set -e

# Check prerequisites. If full, check all prerequisites. Otherwise, just the immediate necessary ones.
if $FULL_CHECK; then
  # Full check: PetaLinux environment and prerequisites
  ./scripts/check/petalinux_env.sh ${BRD} ${VER} ${PRJ} --full
else
  # Minimum check: PetaLinux environment
  ./scripts/check/petalinux_env.sh ${BRD} ${VER} ${PRJ}
fi

# Check that the necessary PetaLinux project exists
if [ ! -d "tmp/${BRD}/${VER}/${PRJ}/petalinux" ]; then
  echo "[CHECK PTLNX PROJECT] ERROR:"
  echo "Missing PetaLinux project directory for ${PBV}"
  echo " Path: tmp/${BRD}/${VER}/${PRJ}/petalinux"
  echo "First run the following command:"
  echo
  echo " make BOARD=${BRD} BOARD_VER=${VER} PROJECT=${PRJ} petalinux"
  echo
  exit 1
fi
