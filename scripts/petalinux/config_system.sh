#!/bin/bash
# Create a patch file for the PetaLinux system configuration
# Requires a terminal of at least 80 columns and 19 lines
# Arguments: <board_name> <board_version> <project_name>
if [ $# -ne 3 ]; then
  echo "Usage: $0 <board_name> <board_version> <project_name>"
  exit 1
fi

# Check if terminal is at least 80 columns wide and 19 lines tall
# This is required to display the PetaLinux configuration menu properly
if [ $(tput cols) -lt 80 ] || [ $(tput lines) -lt 19 ]; then
  echo "[PTLNX SYS CFG] ERROR:"
  echo "Terminal must be at least 80 columns wide and 19 lines tall to use the PetaLinux configuration menu."
  exit 1
fi

# Store the positional parameters in named variables and clear them
# (Petalinux settings script requires no positional parameters)
CMD=${0}
BRD=${1}
VER=${2}
PRJ=${3}
PBV="project \"${PRJ}\" and board \"${BRD}\" v${VER}"
set --

# Check for the XSA file and the PetaLinux system config file
echo "[PTLNX SYS CFG] Checking XSA file and PetaLinux config directory for ${PBV}"
./scripts/check/xsa_file.sh ${BRD} ${VER} ${PRJ} || exit 1
./scripts/check/petalinux_cfg_dir.sh ${BRD} ${VER} ${PRJ} || exit 1

# Extract the PetaLinux year from the version string
if [[ "$PETALINUX_VERSION" =~ ^([0-9]{4}) ]]; then
  PETALINUX_YEAR=${BASH_REMATCH[1]}
else
  echo "[PTLNX SYS CFG] ERROR: Invalid PetaLinux version format (${PETALINUX_VERSION}). Expected format: YYYY.X"
  exit 1
fi

# Check if the config patch file exists and prompt user for update
CONFIG_PATCH_PATH="projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/config.patch"
if [ -f "${CONFIG_PATCH_PATH}" ]; then
  echo "[PTLNX SYS CFG] PetaLinux system configuration patch file already exists at ${CONFIG_PATCH_PATH}"
  read -p "Do you want to update the PetaLinux system configuration? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "[PTLNX SYS CFG] Cancelling PetaLinux system configuration update"
    exit 0
  fi
else
  echo "[PTLNX SYS CFG] Creating new PetaLinux system configuration patch file at ${CONFIG_PATCH_PATH}"
fi

# Source the PetaLinux settings script (make sure to clear positional parameters first)
source ${PETALINUX_PATH}/settings.sh

# Create a new template project
cd tmp
if [ -d "petalinux_template" ]; then
  rm -rf petalinux_template
fi
mkdir petalinux_template
cd petalinux_template
if [ "$PETALINUX_YEAR" -lt 2024 ]; then
  echo "[PTLNX SYS CFG] Using legacy PetaLinux project creation command for year ${PETALINUX_YEAR}"
  petalinux-create -t project --template zynq --name petalinux --force
else
  echo "[PTLNX SYS CFG] Using PetaLinux project creation python arguments (for year ${PETALINUX_YEAR})"
  petalinux-create project --template zynq --name petalinux --force
fi
cd petalinux

# Initialize the default project configuration
echo "[PTLNX SYS CFG] Initializing default PetaLinux system configuration"
petalinux-config --get-hw-description ../../${BRD}/${VER}/${PRJ}/hw_def.xsa --silentconfig

# Check that the PetaLinux version matches the environment variable
PETALINUX_CONF_PATH="components/yocto/layers/meta-petalinux/conf/distro/include/petalinux-version.conf"
if [ -f "$PETALINUX_CONF_PATH" ]; then
  CONF_XILINX_VER_MAIN=$(grep -oP '(?<=XILINX_VER_MAIN = ")[^"]+' "$PETALINUX_CONF_PATH")
  if [ "$PETALINUX_VERSION" != "$CONF_XILINX_VER_MAIN" ]; then
    echo "[PTLNX SYS CFG] ERROR: PETALINUX_VERSION (${PETALINUX_VERSION}) does not match XILINX_VER_MAIN (${CONF_XILINX_VER_MAIN}) in petalinux-version.conf. This likely means you have the wrong or missing PETALINUX_VERSION environment variable set."
    exit 1
  fi
else
  echo "[PTLNX SYS CFG] ERROR: petalinux-version.conf not found at $PETALINUX_CONF_PATH"
  exit 1
fi

# Copy the default project configuration
echo "[PTLNX SYS CFG] Saving default PetaLinux system configuration"
cp project-spec/configs/config project-spec/configs/config.default

# If updating, apply the existing patch
if [ -f "${REV_D_DIR}/${CONFIG_PATCH_PATH}" ]; then
  echo "[PTLNX SYS CFG] Applying existing PetaLinux system configuration patch"
  patch project-spec/configs/config ${REV_D_DIR}/${CONFIG_PATCH_PATH}
fi

# Manually configure the project
echo "[PTLNX SYS CFG] Manually configuring project"
petalinux-config

# Create a patch for the project configuration
echo "[PTLNX SYS CFG] Creating PetaLinux system configuration patch"
diff -u project-spec/configs/config.default project-spec/configs/config | \
  tail -n +3 > \
  ${REV_D_DIR}/projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/config.patch

# Replace the patched project configuration with the default
echo "[PTLNX SYS CFG] Restoring default PetaLinux system configuration for template project"
cp project-spec/configs/config.default project-spec/configs/config
