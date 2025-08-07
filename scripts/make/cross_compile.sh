#!/bin/bash
# Cross compile a C program for the Zynq 7020 platform
# Usage: cross_compile.sh <software_folder> <output_file>
if [ $# -ne 2 ]; then
  echo "Usage: $0 <software_folder> <output_file>"
  exit 1
fi

# Check if the specified software folder exists
if [ ! -d "$1" ]; then
  echo "Error: Software folder '$1' does not exist."
  exit 1
fi

# Collect all C files in the specified folder
C_FILES=$(find "$1" -type f -name "*.c")
# Check if any C files were found
if [ -z "$C_FILES" ]; then
  echo "Error: No C files found in '$1'."
  echo "Please ensure the folder contains C source files."
  exit 1
fi

# Collect all subdirectories in the specified folder
INCLUDE_DIRS=$(find "$1" -type d)
# Add include directories to the compiler flags (including the root folder)
INCLUDE_FLAGS="-I$1"  # Include the root folder
for dir in $INCLUDE_DIRS; do
  INCLUDE_FLAGS+=" -I$dir"
done

# Check if arm-linux-gnueabihf-gcc is installed
if ! command -v arm-linux-gnueabihf-gcc &> /dev/null; then
  echo "Error: arm-linux-gnueabihf-gcc is not installed."
  echo "There's a known issue with the gcc-multilib package necessary for PetaLinux having conflicts with the gcc-arm package."
  echo "Try running:"
  echo "  sudo apt install gcc-arm*"
  echo "but you may need to reinstall gcc-multilib to run PetaLinux again"
  exit 1
fi

# Options for Zynq 7020 (ARM Cortex-A9):
#  -static           : Compiles all dependencies into the file
#  -O3               : Optimizes for speed
#  -mcpu=cortex-a9   : Compiles for the cortex-a9 platform
#  -mfpu=neon        : Adds NEON floating point support
#  -mfloat-abi=hard  : Stores floating point inputs in registers, not as integers
echo "$C_FILES" | xargs arm-linux-gnueabihf-gcc -static -O3 -mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard -o "$2" -lm $INCLUDE_FLAGS
