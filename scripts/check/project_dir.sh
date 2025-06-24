#!/bin/bash
# Check the project and configuration directories for a given board and version
# Arguments: <board_name> <board_version> <project_name> [--full]
# Full check: Board files
# Minimum check: None

# Parse arguments
if [ $# -lt 3 ] || [ $# -gt 4 ] || ( [ $# -eq 4 ] && [ "$4" != "--full" ] ); then
  echo "[CHECK PROJECT DIR] ERROR:"
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

# Check that the block design TCL file exists
if [ ! -f "projects/${PRJ}/block_design.tcl" ]; then
  echo "[CHECK PROJECT DIR] ERROR:"
  echo "Block design TCL file not found for project \"${PRJ}\""
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
