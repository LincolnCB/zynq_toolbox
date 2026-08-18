#!/bin/bash
# Open the Vivado GUI on an already-built project for a given board and project.
# Read-only inspection / manual Tcl testing -- this does not build anything; the
# Makefile `vivado_gui` target lists `xpr` as a prerequisite so the project is
# present before this runs.
#
# Arguments: <board_name> <board_version> <project_name> [<mode>]
#   mode: "vm" (default) runs vivado directly on the host display.
#         "container" runs Vivado inside the container with a self-contained
#         VNC server (scripts/docker/vivado-gui-launch.sh) and prints a URL to
#         view it in a browser or VNC client -- works on any host display
#         server, so nothing is forwarded from the host's X server.

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "[VIVADO GUI] ERROR:"
  echo "Usage: $0 <board_name> <board_version> <project_name> [<mode>]"
  exit 1
fi

BRD="$1"
VER="$2"
PRJ="$3"
MODE="${4:-vm}"

PROJECT_DIR="$BRD/$VER/$PRJ"
XPR="tmp/$PROJECT_DIR/project.xpr"

if [ ! -f "$XPR" ]; then
  echo "[VIVADO GUI] ERROR:"
  echo "Missing Vivado project file for project \"$PRJ\" and board \"$BRD\" v$VER"
  echo " Path: $XPR"
  echo "First build it with:"
  echo "  make xpr PROJECT=$PRJ BOARD=$BRD BOARD_VER=$VER"
  exit 1
fi

if [ "$MODE" = "container" ]; then
  COMPOSE_FILE="scripts/docker/docker-compose.yml"

  # Host-side ports (container-side are fixed at 6080/5901). Override if those
  # host ports are already in use, e.g. NOVNC_PORT=7080 make vivado_gui.
  export NOVNC_PORT="${NOVNC_PORT:-6080}"
  export VNC_PORT="${VNC_PORT:-5901}"

  echo
  echo "[VIVADO GUI] Starting Vivado inside the container with a self-contained"
  echo "[VIVADO GUI] VNC server. This works regardless of the host OS or display"
  echo "[VIVADO GUI] server -- nothing is forwarded from the host's X server."
  echo "[VIVADO GUI]"
  echo "[VIVADO GUI] When Vivado has loaded (~20-40 s), connect with EITHER:"
  echo "[VIVADO GUI]   * web browser: http://localhost:${NOVNC_PORT}/vnc.html"
  echo "[VIVADO GUI]   * VNC client:  localhost:${VNC_PORT}"
  echo "[VIVADO GUI]"
  echo "[VIVADO GUI] Quit Vivado (File > Exit) or press Ctrl+C here to stop it."
  echo

  # --service-ports publishes the vivado service's mapped ports. The image
  # entrypoint sources settings64.sh, then runs the in-container launcher.
  exec docker compose -f "$COMPOSE_FILE" run --rm --service-ports vivado \
    scripts/docker/vivado-gui-launch.sh "$XPR"
else
  vivado -nolog -nojournal -mode gui "$XPR"
fi
