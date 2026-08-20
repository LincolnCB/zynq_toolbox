#!/bin/bash
# Open the Vivado GUI on an already-built project for a given board and project.
# Read-only inspection / manual Tcl testing -- this does not build anything; the
# Makefile `vivado_gui` target lists `xpr` as a prerequisite so the project is
# present before this runs.
#
# Arguments: <board_name> <board_version> <project_name> [<mode>]
#   mode "vm" (default): run vivado directly on the host display.
#   mode "container": run Vivado inside the container, rendering to a host X
#     server over X11 (no VNC). Software OpenGL (Mesa llvmpipe) is used, so no
#     host GPU is required. Per platform:
#       * Linux: a nested Xephyr window, which renders correctly whether the
#         host session is Wayland or X11.
#       * macOS: XQuartz over TCP (host.docker.internal:0).
#
# Env overrides: GUI_GEOMETRY (default 1680x1050).

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "[VIVADO GUI] ERROR:"
  echo "Usage: $0 <board_name> <board_version> <project_name> [<mode>]"
  exit 1
fi

BRD="$1"
VER="$2"
PRJ="$3"
MODE="${4:-vm}"

XPR="tmp/$BRD/$VER/$PRJ/project.xpr"

if [ ! -f "$XPR" ]; then
  echo "[VIVADO GUI] ERROR:"
  echo "Missing Vivado project file for project \"$PRJ\" and board \"$BRD\" v$VER"
  echo "  Path: $XPR"
  echo "First build it with:"
  echo "  make xpr PROJECT=$PRJ BOARD=$BRD BOARD_VER=$VER"
  exit 1
fi

if [ "$MODE" != "container" ]; then
  exec vivado -nolog -nojournal -mode gui "$XPR"
fi

# --- container mode: render to a host X server over X11 --------------------
IMAGE="zynq-toolbox-vivado:2024.2"   # built by `docker compose build vivado`
GEOMETRY="${GUI_GEOMETRY:-1680x1050}"

# Env every platform needs: software OpenGL (no host GPU), and no MIT-SHM (the
# client is containerized, so shared-memory pixmaps can't be shared with the
# host X server -- without this the main window renders blank).
COMMON_ENV=(-e LIBGL_ALWAYS_SOFTWARE=1 -e QT_X11_NO_MITSHM=1)
COMMON_MOUNTS=(
  -v vivado-tools:/tools/Xilinx:ro
  -v "$PWD":/workspace/zynq_toolbox
  -w /workspace/zynq_toolbox
)
if [ -t 0 ]; then TTY=(-it); else TTY=(-i); fi

case "$(uname -s)" in
  Linux)
    if ! command -v Xephyr >/dev/null 2>&1; then
      echo "[VIVADO GUI] ERROR: Xephyr (nested X server) not found. Install it:"
      echo "    Fedora/RHEL:    sudo dnf install xorg-x11-server-Xephyr"
      echo "    Debian/Ubuntu:  sudo apt install xserver-xephyr"
      exit 1
    fi

    # Pick a free display number for the nested X server.
    DNUM=2
    while [ -e "/tmp/.X11-unix/X$DNUM" ]; do DNUM=$((DNUM + 1)); done

    echo "[VIVADO GUI] Starting a nested X server (Xephyr) on :$DNUM ($GEOMETRY)."
    echo "[VIVADO GUI] Vivado will open inside that window. Close Vivado"
    echo "[VIVADO GUI] (File > Exit) or press Ctrl+C here to stop it."

    # Xephyr's window is an ordinary host window, so it presents correctly on
    # Wayland or X11 -- unlike forwarding the container's surface to XWayland.
    Xephyr ":$DNUM" -screen "$GEOMETRY" -resizeable -no-host-grab \
      >/tmp/vivado-xephyr.log 2>&1 &
    XEPHYR_PID=$!
    trap 'kill "$XEPHYR_PID" 2>/dev/null || true' EXIT

    for _ in $(seq 1 100); do
      [ -e "/tmp/.X11-unix/X$DNUM" ] && break
      sleep 0.1
    done

    # The container has no host xauth cookie; allow local connections to :DNUM.
    DISPLAY=":$DNUM" xhost +local: >/dev/null 2>&1 || true

    # --ipc=host lets X shared-memory work with the host-side Xephyr; --network
    # none keeps Vivado offline (X11 travels over the mounted unix socket).
    docker run --rm "${TTY[@]}" \
      --ipc=host --network none \
      -e DISPLAY=":$DNUM" \
      -v /tmp/.X11-unix:/tmp/.X11-unix \
      "${COMMON_ENV[@]}" "${COMMON_MOUNTS[@]}" \
      "$IMAGE" scripts/docker/vivado-gui-launch.sh "$XPR"
    ;;

  Darwin)
    if [ ! -d /Applications/Utilities/XQuartz.app ] && [ ! -d /Applications/XQuartz.app ]; then
      echo "[VIVADO GUI] ERROR: XQuartz not found. Install it from https://www.xquartz.org"
      echo "  Then enable XQuartz > Settings > Security > 'Allow connections from"
      echo "  network clients' and restart XQuartz."
      exit 1
    fi
    open -a XQuartz >/dev/null 2>&1 || true
    xhost + 127.0.0.1 >/dev/null 2>&1 || true

    echo "[VIVADO GUI] Vivado will open in an XQuartz window."
    echo "[VIVADO GUI] Close Vivado (File > Exit) or press Ctrl+C here to stop it."

    # macOS runs Docker in a VM: no host IPC/unix-socket sharing, so reach the
    # host's XQuartz over TCP via host.docker.internal.
    docker run --rm "${TTY[@]}" \
      -e DISPLAY=host.docker.internal:0 \
      "${COMMON_ENV[@]}" "${COMMON_MOUNTS[@]}" \
      "$IMAGE" scripts/docker/vivado-gui-launch.sh "$XPR"
    ;;

  *)
    echo "[VIVADO GUI] ERROR: automatic X11 setup is implemented for Linux and"
    echo "  macOS only. On Windows, start an X server (VcXsrv/X410) with access"
    echo "  control disabled, then run the container manually with"
    echo "  -e DISPLAY=host.docker.internal:0."
    exit 1
    ;;
esac
