#!/bin/bash
# Create a patch file for the PetaLinux project configuration
# Arguments: <board_name> <board_version> <project_name> ['update' (optional)]
if [ $# -ne 3 ] && [ $# -ne 4 ]; then
    echo "Usage: $0 <board_name> <board_version> <project_name> ['update' (optional)]"
    exit 1
fi

# Exit if "update" is not the fourth argument
if [ $# -eq 4 ] && [ "${4}" != "update" ]; then
    echo "Usage: $0 <board_name> <board_version> <project_name> ['update' (optional)]"
    exit 1
fi

# Update is the fourth argument or there is none
if [ $# -eq 4 ] ; then
    UPDATE=1
else
    UPDATE=0
fi

# Check if terminal width is at least 80 columns
if [ $(tput cols) -lt 80 ] || [ $(tput lines) -lt 19 ]; then
    echo "[PTLNX CFG SCRIPT] ERROR:"
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

# Check the PetaLinux requirements
echo "[PTLNX CFG SCRIPT] Checking PetaLinux prerequisites for ${PBV}"
./scripts/check/petalinux_req.sh ${BRD} ${VER} ${PRJ} || exit 1

# Check that the project configuration patch does not already exist if not updating
if [ -f "projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/config.patch" ] && [ $UPDATE -ne 1 ]; then
    echo "[PTLNX CFG SCRIPT] ERROR:"
    echo "PetaLinux version ${PETALINUX_VERSION} project configuration patch already exists for ${PBV}"
    echo "  projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/config.patch"
    echo "If you want to use that patch as the start point, use the following command:"
    echo
    echo "  ${CMD} ${BRD} ${VER} ${PRJ} update"
    exit 1
fi

# Check that the project configuration patch DOES exist if updating
if [ ! -f "projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/config.patch" ] && [ $UPDATE -eq 1 ]; then
    echo "[PTLNX CFG SCRIPT] ERROR:"
    echo "Missing PetaLinux version ${PETALINUX_VERSION} project configuration patch for ${PBV}"
    echo "  projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/config.patch"
    echo "If you want to create a new patch, copy one in or use the following command:"
    echo
    echo "  ${CMD} ${BRD} ${VER} ${PRJ}"
    exit 1
fi

# Source the PetaLinux settings script (make sure to clear positional parameters first)
source ${PETALINUX_PATH}/settings.sh

# Extract the PetaLinux year from the version string
if [[ "$PETALINUX_VERSION" =~ ^([0-9]{4}) ]]; then
    PETALINUX_YEAR=${BASH_REMATCH[1]}
else
    echo "[PTLNX CFG SCRIPT] ERROR: Invalid PetaLinux version format (${PETALINUX_VERSION}). Expected format: YYYY.X"
    exit 1
fi

# Create a new template project
cd tmp
if [ -d "petalinux_template" ]; then
    rm -rf petalinux_template
fi
mkdir petalinux_template
cd petalinux_template
if [ "$PETALINUX_YEAR" -lt 2024 ]; then
    echo "[PTLNX BUILD SCRIPT] Using legacy PetaLinux project creation command for year ${PETALINUX_YEAR}"
    petalinux-create -t project --template zynq --name petalinux --force
else
    echo "[PTLNX BUILD SCRIPT] Using PetaLinux project creation python arguments (for year ${PETALINUX_YEAR})"
    petalinux-create project --template zynq --name petalinux --force
fi
cd petalinux

# Initialize the default project configuration
echo "[PTLNX CFG SCRIPT] Initializing default PetaLinux project configuration"
petalinux-config --get-hw-description ../../${BRD}/${VER}/${PRJ}/hw_def.xsa --silentconfig

# Check that the PetaLinux version matches the environment variable
PETALINUX_CONF_PATH="components/yocto/layers/meta-petalinux/conf/distro/include/petalinux-version.conf"
if [ -f "$PETALINUX_CONF_PATH" ]; then
    CONF_XILINX_VER_MAIN=$(grep -oP '(?<=XILINX_VER_MAIN = ")[^"]+' "$PETALINUX_CONF_PATH")
    if [ "$PETALINUX_VERSION" != "$CONF_XILINX_VER_MAIN" ]; then
        echo "[PTLNX CFG SCRIPT] ERROR: PETALINUX_VERSION (${PETALINUX_VERSION}) does not match XILINX_VER_MAIN (${CONF_XILINX_VER_MAIN}) in petalinux-version.conf. This likely means you have the wrong or missing PETALINUX_VERSION environment variable set."
        exit 1
    fi
else
    echo "[PTLNX CFG SCRIPT] ERROR: petalinux-version.conf not found at $PETALINUX_CONF_PATH"
    exit 1
fi

# Copy the default project configuration
echo "[PTLNX CFG SCRIPT] Saving default PetaLinux project configuration"
cp project-spec/configs/config project-spec/configs/config.default

# If updating, apply the existing patch
if [ $UPDATE -eq 1 ]; then
    echo "[PTLNX CFG SCRIPT] Applying existing PetaLinux project configuration patch"
    patch project-spec/configs/config ../../../projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/config.patch
fi

# Manually configure the project
echo "[PTLNX CFG SCRIPT] Manually configuring project"
petalinux-config

# Create a patch for the project configuration
echo "[PTLNX CFG SCRIPT] Creating PetaLinux project configuration patch"
diff -u project-spec/configs/config.default project-spec/configs/config | \
    tail -n +3 > \
    ../../../projects/${PRJ}/cfg/${BRD}/${VER}/petalinux/${PETALINUX_VERSION}/config.patch

# Replace the patched project configuration with the default
echo "[PTLNX CFG SCRIPT] Restoring default PetaLinux project configuration for template project"
cp project-spec/configs/config.default project-spec/configs/config
