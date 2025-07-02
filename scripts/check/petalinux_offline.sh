#!/bin/bash
# Check the PetaLinux offline path environment variables for a project, board, and version
# Arguments: <board_name> <board_version> <project_name> [--full]
# Full check: PetaLinux project and prerequisites
# Minimum check: None

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
  echo "[CHECK PTLNX OFFLINE] ERROR:"
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
  # Full check: XSA file and prerequisites
  ./scripts/check/petalinux_project.sh ${BRD} ${VER} ${PRJ} --full
fi # Minimum check: None

# Check the PetaLinux offline "downloads" path
if [ -z "$PETALINUX_DOWNLOADS_PATH" ]; then
  echo "[CHECK PTLNX OFFLINE] ERROR: PETALINUX_PATH environment variable is not set."
  exit 1
fi
if [ ! -d "${PETALINUX_DOWNLOADS_PATH}" ]; then
  echo "[CHECK PTLNX OFFLINE] ERROR: PetaLinux offline downloads directory not found at ${PETALINUX_DOWNLOADS_PATH}"
  exit 1
fi

# Check the PetaLinux offline "sstate" path
if [ -z "$PETALINUX_SSTATE_PATH" ]; then
  echo "[CHECK PTLNX OFFLINE] ERROR: PETALINUX_PATH environment variable is not set."
  exit 1
fi
if [ ! -d "${PETALINUX_SSTATE_PATH}" ]; then
  echo "[CHECK PTLNX OFFLINE] ERROR: PetaLinux offline sstate directory not found at ${PETALINUX_SSTATE_PATH}"
  exit 1
fi
