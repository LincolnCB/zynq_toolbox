#!/bin/bash
# Package project files into the PetaLinux root filesystem
# Arguments: <board_name> <board_version> <project_name>
if [ $# -ne 3 ]; then
  echo "[PTLNX ROOTFS PKG] ERROR:"
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

# Check the project directory
./scripts/check/project_dir.sh ${BRD} ${VER} ${PRJ} || exit 1
# Check if there are any files to package
if [ ! -d "projects/${PRJ}/rootfs_include" ]; then
  echo "[PTLNX ROOTFS PKG] No files to package in the root filesystem for ${PBV}"
  echo " Path: projects/${PRJ}/rootfs_include"
  exit 0
fi

# Source the PetaLinux settings script
if [ -z "$PETALINUX_PATH" ]; then
  echo "[PTLNX ROOTFS PKG] ERROR: PETALINUX_PATH environment variable is not set."
  exit 1
fi
if [ ! -f "${PETALINUX_PATH}/settings.sh" ]; then
  echo "[PTLNX ROOTFS PKG] ERROR: PetaLinux settings script not found at ${PETALINUX_PATH}/settings.sh"
  exit 1
fi
source $PETALINUX_PATH/settings.sh

# Check that the necessary PetaLinux project exists
./scripts/check/petalinux_project.sh ${BRD} ${VER} ${PRJ}

# Enter the project
cd tmp/${BRD}/${VER}/${PRJ}/petalinux

# Check that the root filesystem archive exists
if [ ! -d "images/linux" ]; then
  echo "[PTLNX ROOTFS PKG] ERROR:"
  echo "Missing PetaLinux-generated image directory for ${PBV}"
  echo " Path: tmp/${BRD}/${VER}/${PRJ}/petalinux/images/linux"
  echo "First run the following command:"
  echo
  echo " make BOARD=${BRD} BOARD_VER=${VER} PROJECT=${PRJ} petalinux_build"
  echo
  exit 1
fi
# Check that the root filesystem archive exists
if [ ! -f "images/linux/rootfs.tar.gz" ]; then
  echo "[PTLNX ROOTFS PKG] ERROR:"
  echo "Missing PetaLinux-generated root filesystem archive for ${PBV}"
  echo " Path: tmp/${BRD}/${VER}/${PRJ}/petalinux/images/linux/rootfs.tar.gz"
  echo "First run the following command:"
  echo
  echo " make BOARD=${BRD} BOARD_VER=${VER} PROJECT=${PRJ} petalinux_build"
  echo
  exit 1
fi

# Enter the images directory
cd images/linux

# Use tar -tf to get a list of all the users in the root filesystem
users=$(tar -tf rootfs.tar.gz | grep '^./home/[^/]\+/$' | cut -d'/' -f3 | sort -u)
# Remove root from the list of users
users=$(echo "$users" | grep -v '^root$')

# Append the files from the rootfs_include directory into the home/<user> for each user using tar
# Overwrite existing files
echo "[PTLNX ROOTFS PKG] Adding files to the root filesystem for users"
include_dir="../../../../../../../projects/${PRJ}/rootfs_include"
for user in $users; do
  echo "[PTLNX ROOTFS PKG] Including files for user: $user"

  # Uncompress the tar.gz file to a .tar file
  gunzip -c rootfs.tar.gz > rootfs.tar --force

  # Remove files that would be overwritten
  files_to_delete=$(find "$include_dir" -type f -exec basename {} \; | sed "s|^|./home/${user}/|")
  # Check the tar for existing files and filter out non-existent ones
  existing_files=$(tar -tf rootfs.tar)
  files_to_delete=$(echo "$files_to_delete" | while read -r file; do
    if echo "$existing_files" | grep -q "^$file$"; then
      echo "$file"
    fi
  done)
  # Delete any existing files that would be overwritten
  tar --delete --file=rootfs.tar $files_to_delete

  # Append the files from the rootfs_include directory into the home/<user> directory
  tar --append --file=rootfs.tar -C "$include_dir" . --transform "s|^./|./home/${user}/|"
  # Recompress the .tar file back to .tar.gz
  gzip rootfs.tar --force
  if [ $? -ne 0 ]; then
    echo "[PTLNX ROOTFS PKG] ERROR: Failed to append files for user: $user"
    exit 1
  fi
done

