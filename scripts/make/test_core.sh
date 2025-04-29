#!/bin/bash
# Build a PetaLinux project for the given board and project
# Arguments: <vendor> <core>
if [ $# -ne 2 ]; then
    echo "[CORE TEST SCRIPT] ERROR:"
    echo "Usage: $0 <vendor> <core>"
    exit 1
fi

# Store the positional parameters in named variables and clear them
VENDOR=${1}
CORE=${2}
set --

###
# Your code here to create
# custom_cores/${VENDOR}/cores/${CORE}/tests/test_certificate
###