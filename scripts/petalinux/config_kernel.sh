#!/bin/bash
# Configure and manage kernel configuration for a PetaLinux project
# Arguments: <board_name> <board_version> <project_name> <offline>
if [ $# -ne 4 ]; then
  echo "Usage: $0 <board_name> <board_version> <project_name> <offline>"
  exit 1
fi

# Check terminal size
if [ $(tput cols) -lt 80 ] || [ $(tput lines) -lt 21 ]; then
  echo "[PTLNX KERNEL CFG] ERROR: Terminal must be at least 80 columns wide and 21 lines tall."
  exit 1
fi

# Store the positional parameters in named variables and clear them
# (Petalinux settings script requires no positional parameters)
CMD=${0}
BRD=${1}
VER=${2}
PRJ=${3}
OFFLINE=${4}
PBV="project \"${PRJ}\" and board \"${BRD}\" v${VER}"
set --

# If any subsequent command fails, exit immediately
set -e

# Check for the XSA file and the PetaLinux config directory
echo "[PTLNX KERNEL CFG] Checking XSA file and PetaLinux system config file for ${PBV}"
./scripts/check/xsa_file.sh ${BRD} ${VER} ${PRJ} || exit 1
./scripts/check/petalinux_sys_cfg_file.sh ${BRD} ${VER} ${PRJ} || exit 1

# Extract the PetaLinux year from the version string
if [[ "$PETALINUX_VERSION" =~ ^([0-9]{4}) ]]; then
    PETALINUX_YEAR=${BASH_REMATCH[1]}
else
    echo "[PTLNX KERNEL CFG] ERROR: Invalid PetaLinux version format (${PETALINUX_VERSION}). Expected format: YYYY.X"
    exit 1
fi

# Verify the user wants to proceed with updating the PetaLinux kernel configuration if it already exists
KERNEL_CONFIG="projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/kernel_config.cfg"
if [ -f "${KERNEL_CONFIG}" ]; then
  echo "[PTLNX KERNEL CFG] kernel_config.cfg already exists at ${KERNEL_CONFIG}"
  read -p "Do you want to update the kernel configuration? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "[PTLNX KERNEL CFG] Cancelling kernel configuration update"
    exit 0
  fi
else
  echo "[PTLNX KERNEL CFG] Creating new kernel_config.cfg at ${KERNEL_CONFIG}"
fi

# Source the PetaLinux settings script (make sure to clear positional parameters first)
source ${PETALINUX_PATH}/settings.sh

# Create a new template project and enter it
cd tmp
if [ -d "petalinux_template" ]; then
    rm -rf petalinux_template
fi
mkdir petalinux_template
cd petalinux_template
if [ "$PETALINUX_YEAR" -lt 2024 ]; then
    echo "[PTLNX KERNEL CFG] Using legacy PetaLinux project creation command for year ${PETALINUX_YEAR}"
    petalinux-create -t project --template zynq --name petalinux --force
else
    echo "[PTLNX KERNEL CFG] Using PetaLinux project creation python arguments (for year ${PETALINUX_YEAR})"
    petalinux-create project --template zynq --name petalinux --force
fi
cd petalinux


# Initialize the project with the hardware description
echo "[PTLNX KERNEL CFG] Initializing default PetaLinux system configuration"
petalinux-config --get-hw-description ${REV_D_DIR}/tmp/${BRD}/${VER}/${PRJ}/hw_def.xsa --silentconfig

# Check that the PetaLinux version matches the environment variable
PETALINUX_CONF_PATH="components/yocto/layers/meta-petalinux/conf/distro/include/petalinux-version.conf"
if [ -f "$PETALINUX_CONF_PATH" ]; then
    CONF_XILINX_VER_MAIN=$(grep -oP '(?<=XILINX_VER_MAIN = ")[^"]+' "$PETALINUX_CONF_PATH")
    if [ "$PETALINUX_VERSION" != "$CONF_XILINX_VER_MAIN" ]; then
        echo "[PTLNX KERNEL CFG] ERROR: PETALINUX_VERSION (${PETALINUX_VERSION}) does not match XILINX_VER_MAIN (${CONF_XILINX_VER_MAIN}) in petalinux-version.conf. This likely means you have the wrong or missing PETALINUX_VERSION environment variable set"
        exit 1
    fi
else
    echo "[PTLNX KERNEL CFG] ERROR: petalinux-version.conf not found at $PETALINUX_CONF_PATH"
    exit 1
fi

# Patch the project configuration
echo "[PTLNX KERNEL CFG] Patching and configuring PetaLinux project"
patch project-spec/configs/config ${REV_D_DIR}/projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/config.patch
petalinux-config --silentconfig

# Patch the root filesystem configuration
echo "[PTLNX KERNEL CFG] Initializing default PetaLinux root filesystem configuration"
petalinux-config -c rootfs --silentconfig
echo "[PTLNX KERNEL CFG] Patching and configuring PetaLinux root filesystem"
patch project-spec/configs/rootfs_config ${REV_D_DIR}/projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/rootfs_config.patch
petalinux-config -c rootfs --silentconfig

# If OFFLINE, set the project to offline
if [ "$OFFLINE" = "true" ]; then
  echo "[PTLNX KERNEL CFG] Setting PetaLinux project to offline mode"
  cd ${REV_D_DIR}
  ./scripts/petalinux/make_offline.sh petalinux_template
  cd tmp/petalinux_template/petalinux
fi

# If the kernel config file already exists, append all of its lines to the bsp.cfg file
BSP_CFG="project-spec/meta-user/recipes-kernel/linux/linux-xlnx/bsp.cfg"
if [ -f "${REV_D_DIR}/${KERNEL_CONFIG}" ]; then
    echo "[PTLNX KERNEL CFG] Appending existing kernel configuration from ${KERNEL_CONFIG} to bsp.cfg"
    grep '^CONFIG_' "${REV_D_DIR}/${KERNEL_CONFIG}" | while read -r line; do
        if ! grep -Fxq "$line" "${BSP_CFG}"; then
            echo "$line" >> "${BSP_CFG}"
        fi
    done
fi

# Get a list of the files in the project-spec/meta-user/recipes-kernel/linux/linux-xlnx directory
PRE_FILE_LIST=$(ls project-spec/meta-user/recipes-kernel/linux/linux-xlnx)

# Allow user to update kernel config
echo "[PTLNX KERNEL CFG] Launching petalinux-config -c kernel"
petalinux-config -c kernel

# Detect a possible new user config file added to project-spec/meta-user/recipes-kernel/linux/linux-xlnx
NEW_CFG=$(comm -13 <(echo "$PRE_FILE_LIST" | sort) <(ls project-spec/meta-user/recipes-kernel/linux/linux-xlnx | sort) | head -n 1)

# If there's a new user config file, append its contents to the kernel_config.cfg (or copy it if kernel_config.cfg doesn't exist)
if [ -n "$NEW_CFG" ] && [ -f "project-spec/meta-user/recipes-kernel/linux/linux-xlnx/${NEW_CFG}" ]; then
  # Update kernel_config.cfg
  if [ -f "${REV_D_DIR}/${KERNEL_CONFIG}" ]; then
    echo "[PTLNX KERNEL CFG] Appending new kernel config lines to ${KERNEL_CONFIG}"
    grep '^CONFIG_' "project-spec/meta-user/recipes-kernel/linux/linux-xlnx/${NEW_CFG}" >> "${REV_D_DIR}/${KERNEL_CONFIG}"
  else
    echo "[PTLNX KERNEL CFG] Copying new kernel config to ${KERNEL_CONFIG}"
    cp "project-spec/meta-user/recipes-kernel/linux/linux-xlnx/${NEW_CFG}" "${REV_D_DIR}/${KERNEL_CONFIG}"
  fi
fi

# Deduplicate CONFIG_ lines in kernel_config.cfg (keep last occurrence)
if [ -f "${REV_D_DIR}/${KERNEL_CONFIG}" ]; then
  awk '
    {
      # Find CONFIG_ parameter anywhere in the line
      match($0, /CONFIG_[A-Z0-9_]+/)
      param = (RSTART ? substr($0, RSTART, RLENGTH) : "")
      lines[NR] = $0
      params[NR] = param
      if (param != "") last[param] = NR
    }
    END {
      for (i=1; i<=NR; i++) {
        if (params[i] == "" || last[params[i]] == i)
          print lines[i]
      }
    }
  ' "${REV_D_DIR}/${KERNEL_CONFIG}" > "tmp_kernel_config.dedup"
  mv "tmp_kernel_config.dedup" "${REV_D_DIR}/${KERNEL_CONFIG}"

  echo "[PTLNX KERNEL CFG] Kernel configuration updated and deduplicated in ${KERNEL_CONFIG}"
else
  echo "[PTLNX KERNEL CFG] No changes made to kernel configuration."
fi

