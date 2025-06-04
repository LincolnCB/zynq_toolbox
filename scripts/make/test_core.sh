#!/bin/bash
# Build a PetaLinux project for the given board and project
# Arguments: <vendor> <core>
# Usage: test_core.sh <vendor> <core>
# Example:
#   ./scripts/make/test_core.sh lcb hw_manager
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

###
# Your code here to create
# custom_cores/${VENDOR}/cores/${CORE}/tests/test_certificate
###
TEST_DIR="custom_cores/${VENDOR}/cores/${CORE}/tests"

# 1) verify that the tests directory exists
if [ ! -d "${TEST_DIR}" ]; then
  echo "[CORE TESTS] ERROR: Directory not found: ${TEST_DIR}"
  exit 1
fi

# 2) cd into the tests directory
pushd "${TEST_DIR}" >/dev/null

CERT_FILE="test_certificate"

# 3) by default cocotb will create a result.xml file for the test results, remove any old results.xml so we start clean
rm -f results.xml

# 4) run “make <core>_test”
# we assume the Makefile inside tests/ defines a target named exactly "<core>_test"
if ! make "${CORE}_test"; then
  # Makefile itself failed (e.g. Verilator compile error). Mark as failure.
  STATUS="failed tests"
else
  # Make succeeded. Now look for results.xml in this directory.
  if [ -f results.xml ]; then
    # If there's any <failure tag in results.xml, mark as failure
    if grep -q "<failure" results.xml; then
      STATUS="failed tests"
    else
      STATUS="passed tests"
    fi
  else
    # No results.xml produced → assume failure
    STATUS="failed tests"
  fi
fi

# 5) timestamp in “YYYY/MM/DD at HH:MM” (Europe/Istanbul timezone)
DATESTAMP=$(date +"%Y/%m/%d at %H:%M")

# 6) write the certificate line (overwriting old one)
echo "${STATUS} on ${DATESTAMP}" > "${CERT_FILE}"

popd >/dev/null

echo "[CORE TESTS] ${CORE}: ${STATUS} (see ${CERT_FILE})"
exit 0