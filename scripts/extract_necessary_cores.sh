#!/bin/bash

# Check if a file is provided as an argument
if [ $# -eq 0 ]; then
    echo "Usage: $0 <file>"
    exit 1
fi

# Check if the file exists
if [ ! -f "$1" ]; then
    echo "File not found: $1"
    exit 1
fi

# Make a list of strings
strings=()

# Read the file line by line
while IFS= read -r line; do
    if [[ $line == cell* ]]; then
        words=($line)
        strings+=("${words[1]}")
    elif [[ $line == module* ]]; then
        next_line=$(IFS= read -r next_line; echo "$next_line")
        words=($next_line)
        if [[ ${words[0]} != "source" ]]; then
            echo "Invalid module format: $next_line"
            exit 1
        fi
        module_file="${words[1]}"
        if [ ! -f "$module_file" ]; then
            echo "Module file not found: $module_file"
            exit 1
        fi
        $0 "$module_file"
    fi
done < "$1"

# Print the list of strings
for string in "${strings[@]}"; do
    # Split the string by colon
    IFS=":"
    read -ra parts <<< "$string"
    # Check that the string has 4 parts
    if [ ${#parts[@]} -ne 4 ]; then
        echo "Invalid cell format: $string"
        exit 1
    fi
    # If the second part is "user", print the core path
    if [ "${parts[1]}" == "user" ]; then
        echo "${parts[0]}/${parts[2]}"
    fi
done