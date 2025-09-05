#!/bin/bash
# Write an SD card image for the given board and project
# Arguments: <board_name> <board_version> <project_name> [<mount_directory>] [--clean]

CLEAN=0

# Parse arguments and optional --clean flag
ARGS=()
for arg in "$@"; do
  if [ "$arg" == "--clean" ]; then
    CLEAN=1
  else
    ARGS+=("$arg")
  fi
done

if [ ${#ARGS[@]} -lt 3 ] || [ ${#ARGS[@]} -gt 4 ]; then
  echo "[WRITE SD] ERROR:"
  echo "Usage: $0 <board_name> <board_version> <project_name> [<mount_directory>] [--clean]"
  exit 1
fi

BRD=${ARGS[0]}
VER=${ARGS[1]}
PRJ=${ARGS[2]}
if [ ${#ARGS[@]} -eq 4 ]; then
  MNT=${ARGS[3]}
else
  MNT="/media/$(whoami)"
fi
PBV="project \"${PRJ}\" and board \"${BRD}\" v${VER}"

set -e

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

if [ ! -d "${MNT}" ]; then
  echo "[WRITE SD] ERROR:"
  echo "Media/mount directory does not exist: ${MNT}"
  exit 1
fi

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

if [ $CLEAN -eq 1 ]; then
  echo "[WRITE SD] --clean flag detected, running clean_sd.sh..."
  SCRIPT_DIR="$(dirname "$0")"
  bash "${SCRIPT_DIR}/clean_sd.sh" "${MNT}"
fi

echo "[WRITE SD] Unpacking BOOT image for ${PBV} to ${MNT}/BOOT (needs sudo)"
sudo tar -xzf out/${BRD}/${VER}/${PRJ}/BOOT.tar.gz -C ${MNT}/BOOT

echo "[WRITE SD] Unpacking RootFS image for ${PBV} to ${MNT}/RootFS (needs sudo)"
sudo tar -xzf out/${BRD}/${VER}/${PRJ}/rootfs.tar.gz -C ${MNT}/RootFS
