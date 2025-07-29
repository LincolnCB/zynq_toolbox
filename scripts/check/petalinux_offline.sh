#!/bin/bash
# Check the PetaLinux offline path environment variables
# No arguments

# If any subsequent command fails, exit immediately
set -e

# Check the PetaLinux offline "downloads" path
if [ -z "$PETALINUX_DOWNLOADS_PATH" ]; then
  echo "[CHECK PTLNX OFFLINE] ERROR: PETALINUX_PATH environment variable is not set."
  exit 1
fi
if [ ! -d "${PETALINUX_DOWNLOADS_PATH}" ]; then
  echo "[CHECK PTLNX OFFLINE] ERROR: PetaLinux offline downloads directory not found at ${PETALINUX_DOWNLOADS_PATH}"
  exit 1
fi

# Check the PetaLinux offline "sstate" path
if [ -z "$PETALINUX_SSTATE_PATH" ]; then
  echo "[CHECK PTLNX OFFLINE] ERROR: PETALINUX_PATH environment variable is not set."
  exit 1
fi
if [ ! -d "${PETALINUX_SSTATE_PATH}" ]; then
  echo "[CHECK PTLNX OFFLINE] ERROR: PetaLinux offline sstate directory not found at ${PETALINUX_SSTATE_PATH}"
  exit 1
fi
