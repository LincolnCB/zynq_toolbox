#!/bin/bash
# Build a PetaLinux project for the given board and project
# Arguments: <vendor> <core>
# Usage: test_core.sh <vendor> <core>
# Example:
#   ./scripts/make/test_core.sh lcb shim_hw_manager
#
# What it does:
#   1) cd into custom_cores/<vendor>/cores/<core>/tests/
#   2) run “make <core>_test” (this assumes that the Makefile inside tests/ defines a target named exactly "<core>_test")
#   3) if make returns nonzero (e.g. Verilator compile errors), mark “failed tests”
#      else, check results.xml: (if tests are run by default, cocotb will create results.xml) 
#        – if results.xml contains any <failure tags, mark “failed tests”
#        – otherwise mark “passed tests”
#   4) write the one‐line certificate into
#      custom_cores/<vendor>/cores/<core>/tests/test_certificate
#

if [ $# -ne 2 ]; then
  echo "[CORE TESTS] ERROR:"
  echo "Usage: $0 <vendor> <core>"
  exit 1
fi

# Store the positional parameters in named variables and clear them
VENDOR=${1}
CORE=${2}
set --


TEST_DIR="custom_cores/${VENDOR}/cores/${CORE}/tests"

# Verify that the tests directory exists
if [ ! -d "${TEST_DIR}" ]; then
  echo "[CORE TESTS] ERROR: Directory not found: ${TEST_DIR}"
  exit 1
fi

# Enter the tests directory (pushd saves the current directory on a stack)
pushd "${TEST_DIR}" >/dev/null

CERT_FILE="test_certificate"

# Remove any old results.xml for a clean start
rm -f results/results.xml

# Enter the src directory where the Makefile is expected
if [ ! -d "src" ]; then
  echo "[CORE TESTS] ERROR: src directory not found in ${TEST_DIR}"
  popd >/dev/null
  exit 1
fi
pushd src >/dev/null

# Run “make test_custom_core”
# Makefile inside tests/src defines a target "test_custom_core"
mkdir -p ../results  # Ensure results directory exists
if ! make "test_custom_core" > ../results/log.txt; then
  # Makefile itself failed (e.g. Verilator compile error). Mark as failure.
  echo "[CORE TESTS] ERROR: Makefile failed for ${CORE} tests."
  STATUS="failed tests"
else
  # Make succeeded. Now look for results.xml in the results directory.
  if [ -f ../results/results.xml ]; then
    # If there's any tag starting with "<failure" in results.xml, mark as failure
    if grep -q "<failure" ../results/results.xml; then
      echo "[CORE TESTS] ERROR: Found failure tags in results.xml for ${CORE} tests."
      STATUS="failed tests"
    else
      STATUS="passed tests"
    fi
  else
    # Failure if results.xml is not found
    echo "[CORE TESTS] ERROR: No results.xml found in ${TEST_DIR}/results" 
    STATUS="failed tests"
  fi
fi

# Timestamp in “YYYY/MM/DD at HH:MM" format with timezone
DATESTAMP=$(date +"%Y/%m/%d at %H:%M %Z")

if [ "${STATUS}" == "failed tests" ]; then
  echo "[CORE TESTS] ERROR: ${CORE} tests failed."
  echo "See log.txt for details: ${TEST_DIR}/results/log.txt"
  popd >/dev/null
  popd >/dev/null
  exit 1
fi

# Go back up to the tests directory
popd >/dev/null

# Write the certificate line (overwriting old one)
echo "${STATUS} on ${DATESTAMP}" > "${CERT_FILE}"

# Return to the original directory
popd >/dev/null

echo "[CORE TESTS] ${CORE}: ${STATUS} (see ${TEST_DIR}/${CERT_FILE} and ${TEST_DIR}/results/log.txt for details)"
exit 0
