#!/bin/bash
# Runs INSIDE the vivado container (invoked by scripts/vivado/open_gui.sh in
# container mode). Starts a self-contained X server + VNC + noVNC and launches
# the Vivado GUI on it, so it is viewable from any host via a browser or VNC
# client -- nothing is forwarded from the host's X server.
#
# Arguments: <xpr_path>   project.xpr path relative to the repo root
set -e

XPR="$1"
if [ -z "$XPR" ]; then
  echo "[vivado-gui-launch] ERROR: no .xpr path given" >&2
  exit 1
fi

DISPLAY_NUM=":1"
VNC_PORT=5901          # container-side; the host port is mapped by docker
NOVNC_PORT=6080        # container-side; the host port is mapped by docker
GEOMETRY="${GUI_GEOMETRY:-1680x1050}"

# Software OpenGL via Mesa llvmpipe -- the container has no GPU. Vivado renders
# into the in-container X server (which VNC streams out).
export LIBGL_ALWAYS_SOFTWARE=1
export DISPLAY="$DISPLAY_NUM"

VNC_BIN="$(command -v Xtigervnc || command -v Xvnc || true)"
if [ -z "$VNC_BIN" ]; then
  echo "[vivado-gui-launch] ERROR: no TigerVNC server (Xtigervnc/Xvnc) in image" >&2
  exit 1
fi

cleanup() {
  kill "$VNC_PID" "$WM_PID" "$WEB_PID" 2>/dev/null || true
}
trap cleanup EXIT

# In-container X server with a built-in VNC server. No password: the VNC port is
# only reachable through the port docker maps to 127.0.0.1 on the host.
"$VNC_BIN" "$DISPLAY_NUM" -geometry "$GEOMETRY" -depth 24 \
  -SecurityTypes None -rfbport "$VNC_PORT" -AlwaysShared -desktop vivado \
  >/tmp/xvnc.log 2>&1 &
VNC_PID=$!

# Wait for the X socket before starting any X clients.
for _ in $(seq 1 100); do
  [ -S "/tmp/.X11-unix/X${DISPLAY_NUM#:}" ] && break
  sleep 0.1
done

# Lightweight window manager so Vivado's dialogs/menus place and move correctly.
fluxbox >/tmp/fluxbox.log 2>&1 &
WM_PID=$!

# noVNC (browser client) bridging the raw VNC port over WebSocket.
websockify --web=/usr/share/novnc "$NOVNC_PORT" "localhost:$VNC_PORT" \
  >/tmp/novnc.log 2>&1 &
WEB_PID=$!

# Foreground Vivado; when it exits, the trap tears down the helpers and the
# --rm container stops. Run from the project's build dir so stray Vivado files
# (vivado_pid*.str, .Xil) land under tmp/ instead of the repo root.
cd "$(dirname "$XPR")"
vivado -nolog -nojournal -mode gui "$(basename "$XPR")"
