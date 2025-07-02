#!/bin/bash
# Check if the board files for a board and version exist
# Arguments: <board_name> <board_version>

# Parse arguments
if [ $# -ne 2 ]; then
  echo "[CHECK BOARD FILES] ERROR:"
  echo "Usage: $0 <board_name> <board_version>"
fi

# Store the positional parameters in named variables and clear them
BRD=${1}
VER=${2}
set --

# If any subsequent command fails, exit immediately
set -e

# Check that the board folder exists
if [ ! -d "boards/${BRD}" ]; then
  echo "[CHECK BOARD FILES] ERROR:"
  echo "Board folder for board \"${BRD}\" does not exist"
  echo " Path: boards/${BRD}/"
  exit 1
fi

# Check that the board files for the specified version exist
if [ ! -f "boards/${BRD}/board_files/${VER}/board.xml" ]; then
  echo "[CHECK BOARD FILES] ERROR:"
  echo "Board file for version \"${VER}\" of board \"${BRD}\" does not exist (make sure to get ALL the board files)"
  echo " Path: boards/${BRD}/board_files/${VER}/board.xml"
  exit 1
fi
