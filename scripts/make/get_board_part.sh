# filepath: /home/lcb-virt/Documents/rev_d_shim/scripts/make/get_board_part.sh
#!/bin/bash
# Get the vendor, board name, component name, and file version from the XML file for the given board and version
# Arguments: <board_name> <board_version>
if [ $# -ne 2 ]; then
  echo "[GET BOARD PART] ERROR:"
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

# Extract and print the required information
VENDOR=$(grep -oP '<board .*vendor="\K[^"]+' "$XML_FILE" || echo "")
NAME=$(grep -oP '<board .*vendor="[^"]+" name="\K[^"]+' "$XML_FILE" || echo "")
COMPONENT=$(grep -oP '<component name="\K[^"]+' "$XML_FILE" | head -n 1 || echo "")
FILE_VERSION=$(grep -oP '<file_version>\K[^<]+' "$XML_FILE" || echo "")

# Check if any of the variables are empty
if [ -z "$VENDOR" ] || [ -z "$NAME" ] || [ -z "$COMPONENT" ] || [ -z "$FILE_VERSION" ]; then
  exit 1
fi

echo "$VENDOR:$NAME:$COMPONENT:$FILE_VERSION"
