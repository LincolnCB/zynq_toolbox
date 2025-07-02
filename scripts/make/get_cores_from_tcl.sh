#!/bin/bash
# This script reads a tcl block design file and extracts the paths of custom cores instantiated with the "cell" procedure.
# The script can recurse into tcl files sourced by the "module" procedure.

# Check if two arguments are provided
if [ $# -ne 1 ]; then
  echo "Usage: $0 <file>"
  exit 1
fi

# Assign arguments to variables
file="$1"

# Check if the file exists
if [ ! -f "$file" ]; then
  echo "File not found: $file"
  exit 1
fi

# Pull out the project name from the file path (file will be formatted as projects/<project_name>/...tcl)
project=$(echo "$file" | cut -d'/' -f2)


## Pull out the cores from the tcl file
# Initialize the list of paths to IP source file locations
paths=()
# Read the file line by line to capture paths
while IFS= read -r line; do
  # Capture the name of any IPs instantiated with the "cell" procedure (allow leading whitespace)
  if [[ $line =~ ^[[:space:]]*cell ]]; then
    words=($line)

    # Check that the line has at least 2 words
    if [ ${#words[@]} -lt 2 ]; then
      echo "Invalid cell format: $line"
      exit 1
    fi

    # Split the second word by colon
    IFS=":"
    read -ra parts <<< "${words[1]}"
    IFS=" "
    # Check that the second word has at least 2 parts
    if [ ${#parts[@]} -lt 2 ]; then
      echo "Invalid IP name format: ${words[1]}"
      echo "Invalid cell format: $line"
      exit 1
    fi

    # If the second part is "user", add the formatted path to the list of paths
    if [ "${parts[1]}" == "user" ]; then
      # Check that there are at least 3 parts
      if [ ${#parts[@]} -lt 3 ]; then
        echo "Invalid user cell format: $string"
        exit 1
      fi
      paths+=("${parts[0]}/${parts[2]}")
    fi

  # Otherwise, if the line is a module (allow leading whitespace), 
  #  call the script recursively on the tcl script sourced by the module
  elif [[ $line =~ ^[[:space:]]*module ]]; then
    words=($line)

    # Check that the line has at least 3 words
    if [ ${#words[@]} -lt 3 ]; then
      echo "Invalid module format: $line"
      exit 1
    fi

    # Extract the module name and file path
    module_name="${words[1]}"
    module_file="projects/${project}/modules/${module_name}.tcl"

    # Check if the module file exists
    if [ ! -f "$module_file" ]; then
      echo "Module file not found: $module_file"
      exit 1
    fi

    # Call the script recursively on the module file
    output=$($0 "$module_file")

    # Check if the return code is non-zero
    if [ $? -ne 0 ]; then
      echo "Error when parsing $module_file"
      exit 1
    fi

    # Split the output by words
    words=($output)

    # Append each word to the list of core paths
    for word in "${words[@]}"; do
      paths+=("$word")
    done
  fi
done < "$file"

# Sort the list of paths
IFS=$'\n' paths=($(sort <<<"${paths[*]}"))

# Deduplicate the list of paths
paths=($(echo "${paths[@]}" | tr ' ' '\n' | uniq))

# Check if the tail of any path (by /) is a duplicate of the tail of another path
for path in "${paths[@]}"; do
  tail=$(basename "$path")
  for other_path in "${paths[@]}"; do
    other_tail=$(basename "$other_path")
    if [ "$path" != "$other_path" ] && [ "$tail" == "$other_tail" ]; then
      echo "ERROR -- Duplicate custom core name: $tail"
      echo "      -- Paths: $path, $other_path"
      echo "      -- Please rename one of the cores"
      exit 1
    fi
  done
done

# Print the list of paths
for path in "${paths[@]}"; do
  echo "$path"
done
