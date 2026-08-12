#!/bin/bash
# Check a project's optional boot script for validity.
# Arguments: <board_name> <board_version> <project_name> [--full]
# The boot script is optional; if projects/<project>/boot_script.sh does not
# exist this is a no-op. If it does exist it must be a regular, executable file
# (the boot-script recipe runs it via /etc/init.d, and the repo convention is an
# executable script -- see projects/README.md).

# Parse arguments
FULL_CHECK=false
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--full" ]]; then
    FULL_CHECK=true
  else
    ARGS+=("$arg")
  fi
done

# There must be exactly 3 positional arguments (board, version, project)
if [ "${#ARGS[@]}" -ne 3 ]; then
  echo "[CHECK BOOT SCRIPT] ERROR:"
  echo "Usage: $0 <board_name> <board_version> <project_name> [--full]"
  exit 1
fi

BRD="${ARGS[0]}"
VER="${ARGS[1]}"
PRJ="${ARGS[2]}"
set --

# If any subsequent command fails, exit immediately
set -e

# On a full check, run the project directory check first (the boot script only
# makes sense in the context of an existing project).
if $FULL_CHECK; then
  ./scripts/check/project_dir.sh ${BRD} ${VER} ${PRJ} --full
fi

# The boot script is optional -- nothing to validate if it's absent.
BOOT_SCRIPT="projects/${PRJ}/boot_script.sh"
if [ ! -e "${BOOT_SCRIPT}" ]; then
  exit 0
fi

# If present, it must be a regular file...
if [ ! -f "${BOOT_SCRIPT}" ]; then
  echo "[CHECK BOOT SCRIPT] ERROR:"
  echo "Boot script is not a regular file: ${BOOT_SCRIPT}"
  exit 1
fi

# ...and executable, matching the documented convention.
if [ ! -x "${BOOT_SCRIPT}" ]; then
  echo "[CHECK BOOT SCRIPT] ERROR:"
  echo "Boot script is not executable: ${BOOT_SCRIPT}"
  echo "Fix it with:"
  echo
  echo "  chmod +x ${BOOT_SCRIPT}"
  echo
  exit 1
fi

echo "[CHECK BOOT SCRIPT] OK: ${BOOT_SCRIPT}"
