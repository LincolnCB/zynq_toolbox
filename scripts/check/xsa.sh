#!/bin/bash
# Check if the XSA for a project exists
# Arguments: <board_name> <board_version> <project_name>
if [ $# -ne 3 ]; then
    echo "[CHECK XSA] ERROR:"
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

# Check project
./scripts/check/project.sh ${BRD} ${VER} ${PRJ}

# Check that the necessary XSA exists
if [ ! -f "tmp/${BRD}/${VER}/${PRJ}/hw_def.xsa" ]; then
    echo "[CHECK XSA] ERROR:"
    echo "Missing Vivado-generated XSA hardware definition file for ${PBV}"
    echo " Path: tmp/${BRD}/${VER}/${PRJ}/hw_def.xsa."
    echo "First run the following command:"
    echo
    echo " Path: make BOARD=${BRD} BOARD_VER=${VER} PROJECT=${PRJ} xsa"
    echo
    exit 1
fi
