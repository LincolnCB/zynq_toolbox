#!/bin/bash
# Check the project and configuration directories for a given board and version
# Arguments: <board_name> <board_version> <project_name> [--full]
# Full check: Board files
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
  echo "[CHECK PROJECT DIR] ERROR:"
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
  # Full check: Board files
  ./scripts/check/board_files.sh ${BRD} ${VER}
fi # Minimum check: None

# Check that the project exists in "projects"
if [ ! -d "projects/${PRJ}" ]; then
  echo "[CHECK PROJECT DIR] ERROR:"
  echo "Repository project directory not found for project \"${PRJ}\""
  echo " Path: projects/${PRJ}"
  exit 1
fi

# Check that the block design Tcl file exists
if [ ! -f "projects/${PRJ}/block_design.tcl" ]; then
  echo "[CHECK PROJECT DIR] ERROR:"
  echo "Block design Tcl file not found for project \"${PRJ}\""
  echo " Path: projects/${PRJ}/block_design.tcl"
  exit 1
fi

# Check that the configuration folder for the board exists
if [ ! -d "projects/${PRJ}/cfg/${BRD}" ]; then
  echo "[CHECK PROJECT DIR] ERROR:"
  echo "Configuration folder not found for board \"${BRD}\" in project \"${PRJ}\""
  echo " Path: projects/${PRJ}/cfg/${BRD}"
  exit 1
fi

# Check that the configuration folder for the board version exists
if [ ! -d "projects/${PRJ}/cfg/${BRD}/${VER}" ]; then
  echo "[CHECK PROJECT DIR] ERROR:"
  echo "Configuration folder not found for ${PBV}"
  echo " Path: projects/${PRJ}/cfg/${BRD}/${VER}"
  exit 1
fi

# Check that the design constraints folder exists and is not empty
if [ ! -d "projects/${PRJ}/cfg/${BRD}/${VER}/xdc" ] || [ -z "$(ls -A projects/${PRJ}/cfg/${BRD}/${VER}/xdc/*.xdc 2>/dev/null)" ]; then
  echo "[CHECK PROJECT DIR] ERROR:"
  echo "Design constraints folder does not exist or is empty for ${PBV}"
  echo " Path: projects/${PRJ}/cfg/${BRD}/${VER}/xdc"
  exit 1
fi
