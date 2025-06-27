#!/bin/bash
# Clean the BOOT and RootFS directories on the mounted SD card.
# Argument: [<mount_directory>]
if [ $# -gt 1 ]; then
  echo "[CLEAR SD] ERROR:"
  echo "Usage: $0 [<mount_directory>]"
  exit 1
fi

if [ $# -eq 1 ]; then
  MNT=${1}
else
  MNT="/media/$(whoami)"
fi

# If any subsequent command fails, exit immediately
set -e

# Check that the media directory exists
if [ ! -d "${MNT}" ]; then
  echo "[CLEAR SD] ERROR:"
  echo "Media/mount directory does not exist: ${MNT}"
  exit 1
fi

# Check that BOOT and RootFS directories exist
if [ ! -d "${MNT}/BOOT" ]; then
  echo "[CLEAR SD] ERROR:"
  echo "Missing BOOT directory in mount point: ${MNT}/BOOT"
  echo "Ensure the SD card is partitioned and mounted correctly."
  exit 1
fi
if [ ! -d "${MNT}/RootFS" ]; then
  echo "[CLEAR SD] ERROR:"
  echo "Missing RootFS directory in mount point: ${MNT}/RootFS"
  echo "Ensure the SD card is partitioned and mounted correctly."
  exit 1
fi

# Verify with a confirmation prompt
echo "[CLEAR SD] WARNING: This will clear the BOOT and RootFS directories at ${MNT}"
echo "[CLEAR SD] Are you sure you want to proceed? (y/n)"
read -r CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "[CLEAR SD] Aborting."
  exit 0
fi
echo "[CLEAR SD] Proceeding to clear BOOT and RootFS directories at ${MNT}"

# Clear the BOOT directory
echo "[CLEAR SD] Clearing BOOT directory at ${MNT}/BOOT (needs sudo)"
sudo rm -rf ${MNT}/BOOT/*

# Clear the RootFS directory
echo "[CLEAR SD] Clearing RootFS directory at ${MNT}/RootFS (needs sudo)"
sudo rm -rf ${MNT}/RootFS/*

echo "[CLEAR SD] Successfully cleared BOOT and RootFS directories"
