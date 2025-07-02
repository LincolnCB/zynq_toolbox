#!/bin/bash
# Cross compile a C program for the Zynq 7020 platform
# Usage: cross_compile.sh <source_file> <output_file>
if [ $# -ne 2 ]; then
  echo "Usage: $0 <source_file> <output_file>"
  exit 1
fi

# Options for Zynq 7020 (ARM Cortex-A9):
#  -static           : Compiles all dependencies into the file
#  -O3               : Optimizes for speed
#  -mcpu=cortex-a9   : Compiles for the cortex-a9 platform
#  -mfpu=neon        : Adds NEON floating point support
#  -mfloat-abi=hard  : Stores floating point inputs in registers, not as integers
arm-linux-gnueabihf-gcc -static -O3 -mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard $1 -o $2 -lm
