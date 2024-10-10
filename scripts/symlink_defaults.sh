#!/bin/bash

# Check if a file is provided as an argument
if [ ! $# -eq 2 ]; then
    echo "Usage: $0 <project> <board>"
    exit 1
fi

# Check if the project exists in "projects"
if [ ! -d "projects/$1" ]; then
    echo "Project not found: $1"
    exit 1
fi

# Check if the board exists in "boards"
if [ ! -d "boards/$2" ]; then
    echo "Board not found: $2"
    exit 1
fi

# Make sure the file "default_ports.tcl" and the directory "default_xdc" exist in the board directory
if [ ! -f "boards/$2/default_ports.tcl" ]; then
    echo "Default ports TCL file (ports declaration) not found: boards/$2/default_ports.tcl"
    exit 1
fi
if [ ! -d "boards/$2/default_xdc" ]; then
    echo "Default XDC (design constraints) directory not found: boards/$2/default_xdc"
    exit 1
fi

# Cd into the given project directory and create symlinks to the default ports and XDC files
cd "projects/$1"
ln -s "../../boards/$2/default_ports.tcl" "ports.tcl"
ln -s "../../boards/$2/default_xdc" "$2_xdc"

