#!/bin/bash

# Check if the input string is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <input_string>"
    exit 1
fi

input_string=$1

# Read the input string into an array
readarray -t paths <<< "$input_string"

# Concatenate the list and then re-split it into an array by spaces
# This helps handle situations where the input string was already concatenated (e.g. from a Makefile variable)
IFS=" " read -r -a paths <<< "${paths[@]}"

# Iterate over the paths array
for path in "${paths[@]}"; do
    # Get the top-level directory for each path
    top_level_dir=$(dirname "$path")

    # Output the top-level directory
    echo "$top_level_dir"
done | sort -u # Sort and remove duplicates
