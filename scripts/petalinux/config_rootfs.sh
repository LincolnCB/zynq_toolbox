#!/bin/bash
# Create a patch file for the PetaLinux filesystem configuration
# Requires a terminal of at least 80 columns and 19 lines
# Arguments: <board_name> <board_version> <project_name>
if [ $# -ne 3 ]; then
    echo "Usage: $0 <board_name> <board_version> <project_name>"
    exit 1
fi

# Check if terminal is at least 80 columns wide and 19 lines tall
# This is required to display the PetaLinux configuration menu properly
if [ $(tput cols) -lt 80 ] || [ $(tput lines) -lt 19 ]; then
    echo "Terminal must be at least 80 columns wide and 19 lines tall to use the PetaLinux configuration menu"
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

# Check for the XSA file and the PetaLinux config directory
echo "[PTLNX ROOTFS CFG] Checking XSA file and PetaLinux system config file for ${PBV}"
./scripts/check/xsa_file.sh ${BRD} ${VER} ${PRJ} || exit 1
./scripts/check/petalinux_sys_cfg_file.sh ${BRD} ${VER} ${PRJ} || exit 1

# Extract the PetaLinux year from the version string
if [[ "$PETALINUX_VERSION" =~ ^([0-9]{4}) ]]; then
    PETALINUX_YEAR=${BASH_REMATCH[1]}
else
    echo "[PTLNX ROOTFS CFG] ERROR: Invalid PetaLinux version format (${PETALINUX_VERSION}). Expected format: YYYY.X"
    exit 1
fi

# Verify the user wants to proceed with updating the PetaLinux root filesystem configuration if the patch file exists
ROOTFS_CONFIG_PATH="projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/rootfs_config.patch"
if [ -f "${ROOTFS_CONFIG_PATH}" ]; then
    echo "[PTLNX ROOTFS CFG] PetaLinux root filesystem configuration patch file already exists at ${ROOTFS_CONFIG_PATH}"
    read -p "Do you want to update the PetaLinux root filesystem configuration? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "[PTLNX ROOTFS CFG] Cancelling PetaLinux root filesystem configuration update"
        exit 0
    fi
else
    echo "[PTLNX ROOTFS CFG] Creating new PetaLinux root filesystem configuration patch file at ${ROOTFS_CONFIG_PATH}"
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
    echo "[PTLNX ROOTFS CFG] Using legacy PetaLinux project creation command for year ${PETALINUX_YEAR}"
    petalinux-create -t project --template zynq --name petalinux --force
else
    echo "[PTLNX ROOTFS CFG] Using PetaLinux project creation python arguments (for year ${PETALINUX_YEAR})"
    petalinux-create project --template zynq --name petalinux --force
fi
cd petalinux


# Initialize the project with the hardware description
echo "[PTLNX ROOTFS CFG] Initializing default PetaLinux system configuration"
petalinux-config --get-hw-description ../../${BRD}/${VER}/${PRJ}/hw_def.xsa --silentconfig

# Check that the PetaLinux version matches the environment variable
PETALINUX_CONF_PATH="components/yocto/layers/meta-petalinux/conf/distro/include/petalinux-version.conf"
if [ -f "$PETALINUX_CONF_PATH" ]; then
    CONF_XILINX_VER_MAIN=$(grep -oP '(?<=XILINX_VER_MAIN = ")[^"]+' "$PETALINUX_CONF_PATH")
    if [ "$PETALINUX_VERSION" != "$CONF_XILINX_VER_MAIN" ]; then
        echo "[PTLNX ROOTFS CFG] ERROR: PETALINUX_VERSION (${PETALINUX_VERSION}) does not match XILINX_VER_MAIN (${CONF_XILINX_VER_MAIN}) in petalinux-version.conf. This likely means you have the wrong or missing PETALINUX_VERSION environment variable set"
        exit 1
    fi
else
    echo "[PTLNX ROOTFS CFG] ERROR: petalinux-version.conf not found at $PETALINUX_CONF_PATH"
    exit 1
fi

# Patch the project configuration
echo "[PTLNX ROOTFS CFG] Patching and configuring PetaLinux project"
patch project-spec/configs/config ${REV_D_DIR}/projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/config.patch
petalinux-config --silentconfig

# Initialize the default root filesystem configuration
echo "[PTLNX ROOTFS CFG] Initializing default PetaLinux root filesystem configuration"
petalinux-config -c rootfs --silentconfig

# Copy the default root filesystem configuration
echo "[PTLNX ROOTFS CFG] Saving default PetaLinux root filesystem configuration"
cp project-spec/configs/rootfs_config project-spec/configs/rootfs_config.default

# If updating, apply the existing patch
if [ -f "${REV_D_DIR}/${ROOTFS_CONFIG_PATH}" ]; then
    echo "[PTLNX ROOTFS CFG] Applying existing PetaLinux root filesystem configuration patch"
    patch project-spec/configs/rootfs_config ${REV_D_DIR}/${ROOTFS_CONFIG_PATH}
fi

# Manually configure the root filesystem
echo "[PTLNX ROOTFS CFG] Manually configuring PetaLinux root filesystem"
petalinux-config -c rootfs

# Create a patch for the root filesystem configuration
echo "[PTLNX ROOTFS CFG] Creating PetaLinux root filesystem configuration patch"
diff -u project-spec/configs/rootfs_config.default project-spec/configs/rootfs_config | \
    tail -n +3 > \
    ${REV_D_DIR}/projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/rootfs_config.patch

# Replace the root filesystem configuration with the default for the template project
echo "[PTLNX ROOTFS CFG] Restoring default PetaLinux root filesystem configuration for template project"
