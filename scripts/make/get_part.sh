#!/bin/bash
# Get the FPGA part name from the XML file for the given board and version
# Arguments: <board_name> <board_version>
if [ $# -ne 2 ]; then
  echo "[GET PART] ERROR:"
  echo "Usage: $0 <board_name> <board_version>"
  exit 1
fi

# Store the positional parameters in named variables and clear them
BRD=${1}
VER=${2}
set --

# If any subsequent command fails, exit immediately
set -e

# Filepath to the XML file
XML_FILE="boards/${BRD}/board_files/${VER}/board.xml"

# Check if the XML file exists
if [ ! -f "$XML_FILE" ]; then
    exit 1
fi

# Print the FPGA part name
grep -oP 'type="fpga" part_name="\K[^"]+' "$XML_FILE"
