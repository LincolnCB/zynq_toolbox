#!/bin/bash
# Write an SD card image for the given board and project
# Arguments: <board_name> <board_version> <project_name> [<mount_directory>]
if [ $# -lt 3 ] || [ $# -gt 4 ]; then
  echo "[WRITE SD] ERROR:"
  echo "Usage: $0 <board_name> <board_version> <project_name> [<mount_directory>]"
  exit 1
fi

# Store the positional parameters in named variables
BRD=${1}
VER=${2}
PRJ=${3}
if [ $# -eq 4 ]; then
  MNT=${4}
else
  MNT="/media/$(whoami)"
fi
PBV="project \"${PRJ}\" and board \"${BRD}\" v${VER}"
set --

# If any subsequent command fails, exit immediately
set -e

# Check that the output directory exists for `out/BRD/VER/PRJ`
if [ ! -d "out/${BRD}/${VER}/${PRJ}" ]; then
  echo "[WRITE SD] ERROR:"
  echo "Missing project output directory for ${PBV}"
  echo " Path: out/${BRD}/${VER}/${PRJ}"
  echo "First run the following command:"
  echo
  echo " make BOARD=${BRD} BOARD_VER=${VER} PROJECT=${PRJ} sd"
  echo
  exit 1
fi

# Check that the necessary files exist in `out/BRD/VER/PRJ`
if [ ! -f "out/${BRD}/${VER}/${PRJ}/BOOT.tar.gz" ] || [ ! -f "out/${BRD}/${VER}/${PRJ}/rootfs.tar.gz" ]; then
  echo "[WRITE SD] ERROR:"
  echo "Missing required files for ${PBV}"
  echo " Ensure the following files exist:"
  echo "  - out/${BRD}/${VER}/${PRJ}/BOOT.tar.gz"
  echo "  - out/${BRD}/${VER}/${PRJ}/rootfs.tar.gz"
  echo "First run the following command:"
  echo
  echo " make BOARD=${BRD} BOARD_VER=${VER} PROJECT=${PRJ} sd"
  echo
  exit 1
fi

# Check that the media directory exists
if [ ! -d "${MNT}" ]; then
  echo "[WRITE SD] ERROR:"
  echo "Media/mount directory does not exist: ${MNT}"
  exit 1
fi

# Check that BOOT and RootFS directories exist
if [ ! -d "${MNT}/BOOT" ]; then
  echo "[WRITE SD] ERROR:"
  echo "Missing BOOT directory in mount point: ${MNT}/BOOT"
  echo "Ensure the SD card is partitioned and mounted correctly."
  exit 1
fi
if [ ! -d "${MNT}/RootFS" ]; then
  echo "[WRITE SD] ERROR:"
  echo "Missing RootFS directory in mount point: ${MNT}/RootFS"
  echo "Ensure the SD card is partitioned and mounted correctly."
  exit 1
fi

# Unpack the BOOT image
echo "[WRITE SD] Unpacking BOOT image for ${PBV} to ${MNT}/BOOT (needs sudo)"
sudo tar -xzf out/${BRD}/${VER}/${PRJ}/BOOT.tar.gz -C ${MNT}/BOOT

# Unpack the RootFS image
echo "[WRITE SD] Unpacking RootFS image for ${PBV} to ${MNT}/RootFS (needs sudo)"
sudo tar -xzf out/${BRD}/${VER}/${PRJ}/rootfs.tar.gz -C ${MNT}/RootFS
