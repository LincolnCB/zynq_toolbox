#!/bin/bash
# Check the PetaLinux config file for a project, board, and version
# Arguments: <board_name> <board_version> <project_name> [--full]
# Full check: PetaLinux environment and prerequisites
# Minimum check: Project source, XSA file, and PetaLinux environment

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
  echo "[CHECK PTLNX SYS CFG] ERROR:"
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
  # Full check: PetaLinux config directory and prerequisites
  ./scripts/check/petalinux_cfg_dir.sh ${BRD} ${VER} ${PRJ} --full
else
  # Minimum check: PetaLinux config directory (includes project source and PetaLinux environment)
  ./scripts/check/petalinux_cfg_dir.sh ${BRD} ${VER} ${PRJ}
fi

# Check that the necessary PetaLinux system config file exists
if [ ! -f "projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/config.patch" ]; then
  echo "[CHECK PTLNX SYS CFG] ERROR:"
  echo "Missing PetaLinux system configuration patch file for ${PBV}"
  echo " Path: projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/config.patch"
  echo "You can create this file by running the following command:"
  echo
  echo " scripts/petalinux/config_system.sh ${BRD} ${VER} ${PRJ}"
  echo
  exit 1
fi
