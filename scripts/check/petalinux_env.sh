#!/bin/bash
# Check the PetaLinux environment variables for a project, board, and version
# Arguments: <board_name> <board_version> <project_name> [--full]
# Full check: XSA file and prerequisites
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
  echo "[CHECK PTLNX REQ] ERROR:"
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
  ./scripts/check/xsa_file.sh ${BRD} ${VER} ${PRJ} --full
fi # Minimum check: None

# Check that the PetaLinux settings script exists
if [ -z "$PETALINUX_PATH" ]; then
  echo "[CHECK PTLNX REQ] ERROR: PETALINUX_PATH environment variable is not set."
  exit 1
fi

if [ ! -f "${PETALINUX_PATH}/settings.sh" ]; then
  echo "[CHECK PTLNX REQ] ERROR: PetaLinux settings script not found at ${PETALINUX_PATH}/settings.sh"
  exit 1
fi

# Check that the PetaLinux version environment variable is set
if [ -z "$PETALINUX_VERSION" ]; then
  echo "[CHECK PTLNX REQ] ERROR: PETALINUX_VERSION environment variable is not set."
  exit 1
fi

# Check that the PetaLinux version is valid
if [[ ! "$PETALINUX_VERSION" =~ ^[0-9]{4}\.[0-9]+$ ]]; then
  echo "[CHECK PTLNX REQ] ERROR: Invalid PetaLinux version format (${PETALINUX_VERSION}). Expected format: YYYY.X"
  exit 1
fi
