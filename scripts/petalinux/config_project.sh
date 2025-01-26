#!/bin/bash
# Create a patch file for the PetaLinux project configuration
# Arguments: <board_name> <project_name> ['update' (optional)]
if [ $# -ne 2 ] && [ $# -ne 3 ]; then
    echo "Usage: $0 <board_name> <project_name> ['update' (optional)]"
    exit 1
fi

# Exit if "update" is not the third argument
if [ $# -eq 3 ] && [ "${3}" != "update" ]; then
    echo "Usage: $0 <board_name> <project_name> ['update' (optional)]"
    exit 1
fi

# Update is the third argument or there is none
if [ $# -eq 3 ] ; then
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
PRJ=${2}
set --

# Check that the project exists in "projects"
if [ ! -d "projects/${PRJ}" ]; then
    echo "[PTLNX CFG SCRIPT] ERROR:"
    echo "Repository project directory not found: projects/${PRJ}"
    exit 1
fi

# Check that the project configuration patch does not already exist if not updating
if [ -f "projects/${PRJ}/cfg/${BRD}/petalinux/config.patch" ] && [ $UPDATE -ne 1 ]; then
    echo "[PTLNX CFG SCRIPT] ERROR:"
    echo "PetaLinux project configuration patch already exists for project ${PRJ} and board ${BRD}: projects/${PRJ}/cfg/${BRD}/petalinux/config.patch"
    echo "If you want to use that patch as the start point, use the following command:"
    echo
    echo "  ${CMD} ${BRD} ${PRJ} update"
    exit 1
fi

# Check that the project configuration patch DOES exist if updating
if [ ! -f "projects/${PRJ}/cfg/${BRD}/petalinux/config.patch" ] && [ $UPDATE -eq 1 ]; then
    echo "[PTLNX CFG SCRIPT] ERROR:"
    echo "Missing PetaLinux project configuration patch for project ${PRJ} and board ${BRD}: projects/${PRJ}/cfg/${BRD}/petalinux/config.patch"
    echo "If you want to create a new patch, copy one in or use the following command:"
    echo
    echo "  ${CMD} ${BRD} ${PRJ}"
    exit 1
fi


# Check that the necessary XSA exists
if [ ! -f "tmp/${BRD}/${PRJ}/hw_def.xsa" ]; then
    echo "[PTLNX CFG SCRIPT] ERROR:"
    echo "Missing Vivado-generated XSA hardware definition file: tmp/${BRD}/${PRJ}/hw_def.xsa"
    echo "First run the following command:"
    echo
    echo "  make BOARD=${BRD} PROJECT=${PRJ} xsa"
    echo
    exit 1
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
petalinux-create -t project --template zynq --name petalinux
cd petalinux

# Initialize the default project configuration
echo "[PTLNX CFG SCRIPT] Initializing default PetaLinux project configuration"
petalinux-config --get-hw-description ../../${BRD}/${PRJ}/hw_def.xsa --silentconfig

# Copy the default project configuration
echo "[PTLNX CFG SCRIPT] Saving default PetaLinux project configuration"
cp project-spec/configs/config project-spec/configs/config.default

# If updating, apply the existing patch
if [ $UPDATE -eq 1 ]; then
    echo "[PTLNX CFG SCRIPT] Applying existing PetaLinux project configuration patch"
    patch project-spec/configs/config ../../../projects/${PRJ}/cfg/${BRD}/petalinux/config.patch
fi

# Manually configure the project
echo "[PTLNX CFG SCRIPT] Manually configuring project"
petalinux-config

# Create a patch for the project configuration
echo "[PTLNX CFG SCRIPT] Creating PetaLinux project configuration patch"
diff -u project-spec/configs/config.default project-spec/configs/config | \
    tail -n +3 > \
    ../../../projects/${PRJ}/cfg/${BRD}/petalinux/config.patch

# Replace the patched project configuration with the default
echo "[PTLNX CFG SCRIPT] Restoring default PetaLinux project configuration for template project"
cp project-spec/configs/config.default project-spec/configs/config
