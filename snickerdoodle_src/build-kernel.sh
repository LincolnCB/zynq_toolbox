#! /bin/bash

# Set achitecture and compilation
XILINX_VITIS_BASE=/tools/Xilinx/Vitis/2024.1
export CROSS_COMPILE=$XILINX_VITIS_BASE/gnu/aarch32/lin/gcc-arm-linux-gnueabi/bin/arm-linux-gnueabihf-
export ARCH=arm

CONFIG_NAME=snickerdoodle_defconfig

BASE=${PWD}
KERNEL_SOURCE=$BASE/rev-d-shim-snickerdoodle-linux
KERNEL_OUT=$BASE/build/kernel

WLINK_SOURCE=$BASE/wlink
WLINK_OUT=$BASE/build/wlink
ROOTFS_PATH=$BASE/build/rootfs
ROOTFS_PATH_TEMP=$BASE/build/rootfs_temp
DEBIAN_PKG_PATH=$BASE/build/debian

# Use 8 cores
CORE_MULT=-j8

PATH=$BASE/build/uboot/tools:$PATH

COMMAND="BUILD"

# Parse the inputs
echo "Key: $1"

while [[ $# > 0 ]]
do
key="$1"

case $key in
    -r|--rebuild)
    COMMAND="REBUILD"
    shift # past argument
    ;;
    -m|--menu)
    COMMAND="MENU"
    shift # past argument
    ;;
    -c|--clean)
    COMMAND="CLEAN"
    shift # past argument
    ;;
		-p|--package)
		COMMAND="PACKAGE"
		shift
		;;
		-s|--scripts)
		COMMAND="SCRIPTS"
		shift
		;;
    *)
    # unknown option
    shift # past argument
    ;;
esac
shift
done

echo "Finished parsing inputs"

cd $KERNEL_SOURCE

if [ "$COMMAND" == "CLEAN" ]; then
  echo "Clean"
  make O=$KERNEL_OUT $CORE_MULT clean
fi
if [ "$COMMAND" == "MENU" ]; then
  echo "Menu Config"
  make O=$KERNEL_OUT $CORE_MULT menuconfig
fi

if [ "$COMMAND" == "REBUILD" -o "$COMMAND" == "SCRIPTS" ]; then
  echo "Re-Build"
	mkdir -p $ROOTFS_PATH
	mkdir -p $ROOTFS_PATH_TEMP
	mkdir -p $DEBIAN_PKG_PATH
  make mrproper
  make O=$KERNEL_OUT $CORE_MULT clean
  make O=$KERNEL_OUT $CORE_MULT distclean
  make O=$KERNEL_OUT $CORE_MULT $CONFIG_NAME
  make O=$KERNEL_OUT $CORE_MULT prepare
	if [ "$COMMAND" == "REBUILD" ]; then
		COMMAND="BUILD"
	fi
fi
if [ "$COMMAND" == "SCRIPTS" ]; then
  make O=$KERNEL_OUT $CORE_MULT scripts
fi
if [ "$COMMAND" == "BUILD" ]; then
	sudo echo "Building Kernel"
	make O=$KERNEL_OUT $CORE_MULT
  echo "Build Kernel uImage"
  make O=$KERNEL_OUT LOADADDR=0x8000 uImage $CORE_MULT
  echo "Remove Previous Modules"
	sudo rm -rf $ROOTFS_PATH_TEMP/*
  echo "Build Modules"
  make O=$KERNEL_OUT $CORE_MULT modules
  echo "Install the modules into a temporary rootfs"
	make O=$KERNEL_OUT INSTALL_MOD_PATH=$ROOTFS_PATH_TEMP modules_install
	echo "Change the owner of the modules to root"
	sudo chown -R root:root $ROOTFS_PATH_TEMP/*
	echo "Copy the modules into the rootfs"
	sudo cp -a $ROOTFS_PATH_TEMP/* $ROOTFS_PATH/
	echo "Done"
fi
if [ "$COMMAND" == "PACKAGE" ]; then
  echo "Build Debian Install Package"
  make O=$KERNEL_OUT $CORE_MULT bindeb-pkg
  sudo mv build/*.changes build/debian/
  sudo mv build/*.deb build/debian/
fi

