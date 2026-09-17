#!/bin/bash
# Tests a custom core with cocotb. Uses the shared Makefile in scripts/make/cocotb.mk.
# Arguments: <project> <vendor> <core>
# Usage: test_core.sh <project> <vendor> <core>
# Example:
#   ./scripts/make/test_core.sh ex02_axi_interface base axi_fifo_bridge
#
# This runs cocotb/Verilator directly, so it needs those tools on PATH. Don't call it
# standalone in Docker mode (MODE=container) -- cocotb lives only inside the cocotb
# container there, and a bare host call fails with "cocotb-config: No such file or
# directory". Drive it through the make targets instead (make tests, or a per-core
# test_status target), which wrap this script in the container via run_cocotb. A direct
# call only works in VM mode, where cocotb is installed on the host.

if [ $# -ne 3 ]; then
  echo "[CORE TESTS] ERROR:"
  echo "Usage: $0 <project> <vendor> <core>"
  exit 1
fi

# Store the positional parameters in named variables and clear them
PROJECT=${1}
VENDOR=${2}
CORE=${3}
set --

TEST_DIR="projects/${PROJECT}/cores/${VENDOR}/${CORE}/tests"

# Verify that the tests directory exists
if [ ! -d "${TEST_DIR}" ]; then
  echo "[CORE TESTS] ERROR: Directory not found: ${TEST_DIR}"
  exit 1
fi

STS_FILE="${TEST_DIR}/test_status"

# Remove any old results.xml for a clean start
rm -f "${TEST_DIR}/results/results.xml"

# Check the src directory where the testbench files
if [ ! -d "${TEST_DIR}/src" ]; then
  echo "[CORE TESTS]: src directory not found in ${TEST_DIR} -- assuming no tests to run."

  # Write a skip on the status file line (overwriting old one)
  echo "NO TESTS (no src directory) as of $(date +"%Y/%m/%d at %H:%M %Z") " > "${STS_FILE}"
  echo "[CORE TESTS] ${CORE}: Tests SKIPPED (see ${TEST_DIR}/${STS_FILE} details)"

  exit 0
fi

# Check if the top-level testbench file exists
if [ ! -f "${TEST_DIR}/src/testbench.py" ]; then
  echo "[CORE TESTS] ERROR: testbench.py not found in ${TEST_DIR}/src"
  echo "Please ensure that the top-level cocotb testbench file is named 'testbench.py'."
  exit 1
fi

echo "[CORE TESTS] Running tests for ${CORE} in ${TEST_DIR} using scripts/make/cocotb.mk"

# Run “make test_custom_core”
# Makefile inside tests/src defines a target "test_custom_core"
mkdir -p "${TEST_DIR}/results"  # Ensure results directory exists

LOG_FILE="${TEST_DIR}/results/log.txt"

# Wall-clock timeout (seconds) so a hung simulation self-terminates instead of blocking
# forever -- a testbench that parks the DUT (infinite wait, huge lockout) never returns on
# its own. Override with CORE_TEST_TIMEOUT; CORE_TEST_KILL_GRACE is how long to wait after
# SIGTERM before escalating to SIGKILL for a child that ignores it (cocotb/Python can).
CORE_TEST_TIMEOUT="${CORE_TEST_TIMEOUT:-600}"
CORE_TEST_KILL_GRACE="${CORE_TEST_KILL_GRACE:-10}"

# Forward Ctrl-C / termination to the test process and record it. With no controlling TTY
# (e.g. `docker compose run -T`) the signal reaches this script but not the make subtree, so
# relay it explicitly; the script then exits and, under `docker compose run --rm`, container
# teardown reaps anything the simulator left behind.
TEST_PID=""
on_signal() {
  local sig="${1}"
  [ -n "${TEST_PID}" ] && kill -TERM "${TEST_PID}" 2>/dev/null
  echo "ABORTED (${sig}) on $(date +"%Y/%m/%d at %H:%M %Z")" > "${STS_FILE}"
  echo "[CORE TESTS] ${CORE}: ABORTED by ${sig} (see ${LOG_FILE} for partial output)"
  case "${sig}" in
    INT)  exit 130 ;;
    *)    exit 143 ;;
  esac
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM

timeout --signal=TERM --kill-after="${CORE_TEST_KILL_GRACE}s" "${CORE_TEST_TIMEOUT}s" \
  make --directory="${TEST_DIR}/src" --file="$(realpath scripts/make/cocotb.mk)" "test_custom_core" \
  > "${LOG_FILE}" 2>&1 &
TEST_PID=$!
wait "${TEST_PID}"
MAKE_RESULT=$?
trap - INT TERM

if [ "${MAKE_RESULT}" -eq 124 ] || [ "${MAKE_RESULT}" -eq 137 ]; then
  # 124 = timed out (SIGTERM); 137 = 128+9, killed after the grace period (SIGKILL)
  echo "[CORE TESTS] ERROR: ${CORE} tests TIMED OUT after ${CORE_TEST_TIMEOUT}s."
  echo "See log.txt for details: ${LOG_FILE}"
  echo "TIMED OUT (after ${CORE_TEST_TIMEOUT}s) on $(date +"%Y/%m/%d at %H:%M %Z")" > "${STS_FILE}"
  echo "See log.txt for details: ${LOG_FILE}" >> "${STS_FILE}"
  exit 1
elif [ "${MAKE_RESULT}" -ne 0 ]; then
  # Makefile itself failed (e.g. Verilator compile error). Mark as failure.
  echo "[CORE TESTS] ERROR: Makefile failed for ${CORE} tests."
  echo "See log.txt for details: ${LOG_FILE}"
  exit 1
else
  # Make succeeded. Now look for results.xml in the results directory.
  if [ -f "${TEST_DIR}/results/results.xml" ]; then
    # If there's any tag starting with "<failure" in results.xml, mark as failure
    if grep -q "<failure" "${TEST_DIR}/results/results.xml"; then
      echo "[CORE TESTS] ERROR: Found failure tags in results.xml for ${CORE} tests."
      STATUS="FAILED tests"
    else
      STATUS="PASSED tests"
    fi
  else
    # Failure if results.xml is not found
    echo "[CORE TESTS] ERROR: No results.xml found in ${TEST_DIR}/results"
    STATUS="FAILED tests"
  fi
fi

# Write the status file line (overwriting old one)
echo "${STATUS} on $(date +"%Y/%m/%d at %H:%M %Z")" > "${STS_FILE}"

# Put extra info if failed
if [ "${STATUS}" == "FAILED tests" ]; then
  echo "See log.txt for details: ${LOG_FILE}" >> "${STS_FILE}"
fi

echo "[CORE TESTS] ${CORE}: ${STATUS} (see ${TEST_DIR}/${STS_FILE} and ${LOG_FILE} for details)"
exit 0
