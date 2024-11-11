#!/bin/bash
# Format a status string for the Makefile log

# Check if a status string was passed
if [ -z "$1" ]; then
  echo "Error: No status string provided."
  echo "Usage: $0 <status_string>"
  exit 1
fi

# Print the status string
status_string="$1"
echo
echo "--------------------------"
echo "---- $status_string"
echo "--------------------------"
echo
