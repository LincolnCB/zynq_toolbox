#!/bin/bash
# Build PetaLinux software for the given project
# Arguments: <petalinux_project>
if [ $# -ne 1 ]; then
  echo "[PTLNX OFFLINE] ERROR:"
  echo "Usage: $0 <petalinux_project>"
  exit 1
fi

# Store the positional parameter in a named variable and clear it
PTLNX_PROJECT=${1}
set --

# If any subsequent command fails, exit immediately
set -e

echo "[PTLNX OFFLINE] Setting PetaLinux project ${PTLNX_PROJECT} up for offline build"
# Check that the PetaLinux project exists
# Check that the necessary PetaLinux project exists
if [ ! -d "tmp/${PTLNX_PROJECT}/petalinux" ]; then
  echo "[CHECK PTLNX PROJECT] ERROR:"
  echo "Missing PetaLinux project directory for ${PTLNX_PROJECT}"
  echo " Path: tmp/${PTLNX_PROJECT}/petalinux"
  exit 1
fi
./scripts/check/petalinux_offline.sh

# Set config file path
cfg_file="tmp/${PTLNX_PROJECT}/petalinux/project-spec/configs/config"


# Get the first line with CONFIG_PRE_MIRROR_URL=".*"
line_n=$(grep -nG "CONFIG_PRE_MIRROR_URL=\".*\"" $cfg_file | head -1 | cut -d : -f 1)
# Replace the line with the local path
sed -i.bak -r "${line_n}c\
CONFIG_PRE_MIRROR_URL=\"file://${PETALINUX_DOWNLOADS_PATH}\"" $cfg_file

# Get the first line with CONFIG_YOCTO_LOCAL_SSTATE_FEEDS_URL
line_n=$(grep -n "CONFIG_YOCTO_LOCAL_SSTATE_FEEDS_URL" $cfg_file | head -1 | cut -d : -f 1)
# Replace the line with the local path
sed -i.bak -r "${line_n}c\
CONFIG_YOCTO_LOCAL_SSTATE_FEEDS_URL=\"${PETALINUX_SSTATE_PATH}\"" $cfg_file

# Get the line range for the CONFIG_YOCTO_NETWORK_SSTATE options
# (starts at CONFIG_YOCTO_NETWORK_SSTATE_FEEDS, ends at the line before CONFIG_YOCTO_BB_NO_NETWORK)
line_start=$(grep -n "CONFIG_YOCTO_NETWORK_SSTATE_FEEDS" $cfg_file | head -1 | cut -d : -f 1)
line_end=$(($(grep -n "CONFIG_YOCTO_BB_NO_NETWORK" $cfg_file | head -1 | cut -d : -f 1) -1))
# Replace the lines with disabled network sstate feeds
sed -i.bak -r "${line_start},${line_end}c\
# CONFIG_YOCTO_NETWORK_SSTATE_FEEDS is not set" $cfg_file

# Get the first line with CONFIG_YOCTO_BB_NO_NETWORK
line_n=$(grep -n "CONFIG_YOCTO_BB_NO_NETWORK" $cfg_file | head -1 | cut -d : -f 1)
# Replace the line with enabled no-network sstate feeds
sed -i.bak -r "${line_n}c\
CONFIG_YOCTO_BB_NO_NETWORK=y" $cfg_file


