#!/bin/bash
# Check if a project exists and is configured for the given board and version
# Arguments: <board_name> <board_version> <project_name>
if [ $# -ne 3 ]; then
    echo "[CHECK PTLNX CFG] ERROR:"
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

# Check the board and version
./scripts/check/board.sh ${BRD} ${VER}

# Check that the project exists in "projects"
if [ ! -d "projects/${PRJ}" ]; then
    echo "[CHECK PROJECT] ERROR:"
    echo "Repository project directory not found for project \"${PRJ}\""
    echo " Path: projects/${PRJ}"
    exit 1
fi

# Check that the block design TCL file exists
if [ ! -f "projects/${PRJ}/block_design.tcl" ]; then
    echo "[CHECK PROJECT] ERROR:"
    echo "Block design TCL file not found for project \"${PRJ}\""
    echo " Path: projects/${PRJ}/block_design.tcl"
    exit 1
fi

# Check that the ports TCL file exists
if [ ! -f "projects/${PRJ}/ports.tcl" ]; then
    echo "[CHECK PROJECT] ERROR:"
    echo "Ports TCL file not found for project \"${PRJ}\""
    echo " Path: projects/${PRJ}/ports.tcl"
    exit 1
fi

# Check that the configuration folder for the board exists
if [ ! -d "projects/${PRJ}/cfg/${BRD}" ]; then
    echo "[CHECK PROJECT] ERROR:"
    echo "Configuration folder not found for board \"${BRD}\" in project \"${PRJ}\""
    echo " Path: projects/${PRJ}/cfg/${BRD}"
    exit 1
fi

# Check that the configuration folder for the board version exists
if [ ! -d "projects/${PRJ}/cfg/${BRD}/${VER}" ]; then
    echo "[CHECK PROJECT] ERROR:"
    echo "Configuration folder not found for ${PBV}"
    echo " Path: projects/${PRJ}/cfg/${BRD}/${VER}"
    exit 1
fi

# Check that the design constraints folder exists and is not empty
if [ ! -d "projects/${PRJ}/cfg/${BRD}/${VER}/xdc" ] || [ -z "$(ls -A projects/${PRJ}/cfg/${BRD}/${VER}/xdc/*.xdc 2>/dev/null)" ]; then
    echo "[CHECK PROJECT] ERROR:"
    echo "Design constraints folder does not exist or is empty for ${PBV}"
    echo " Path: projects/${PRJ}/cfg/${BRD}/${VER}/xdc"
    exit 1
fi
