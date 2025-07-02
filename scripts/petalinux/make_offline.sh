#!/bin/bash
# Build PetaLinux software for the given board and project
# Arguments: <board_name> <board_version> <project_name>
if [ $# -ne 3 ]; then
  echo "[PTLNX OFFLINE] ERROR:"
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

echo "[PTLNX OFFLINE] Setting PetaLinux project for ${PBV} up for offline build"
# Check that the PetaLinux project exists
./scripts/check/petalinux_project.sh ${BRD} ${VER} ${PRJ}
./scripts/check/petalinux_offline.sh ${BRD} ${VER} ${PRJ}

# Set config file path
cfg_file="tmp/$BRD/$VER/$PRJ/petalinux/project-spec/configs/config"


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


