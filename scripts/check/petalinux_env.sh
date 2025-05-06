#!/bin/bash
# Check the PetaLinux environment variables for a project, board, and version
# Arguments: <board_name> <board_version> <project_name> [--full]
# Full check: XSA file and prerequisites
# Minimum check: None

# Parse arguments
if [ $# -lt 3 ] || [ $# -gt 4 ] || ( [ $# -eq 4 ] && [ "$4" != "--full" ] ); then
  echo "[CHECK PTLNX REQ] ERROR:"
  echo "Usage: $0 <board_name> <board_version> <project_name> [--full]"
  exit 1
fi
FULL_CHECK=false
if [[ "$4" == "--full" ]]; then
  FULL_CHECK=true
fi

# Store the positional parameters in named variables and clear them
BRD=${1}
VER=${2}
PRJ=${3}
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
