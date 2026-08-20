#!/bin/bash
# Runs INSIDE the vivado container (invoked by scripts/vivado/open_gui.sh in
# container mode). Starts a window manager and the Vivado GUI on the X display
# provided by the host -- a nested Xephyr window on Linux, or XQuartz on macOS.
# Rendering goes straight to that host X server over X11; there is no VNC.
#
# Argument: <xpr_path>   project.xpr path relative to the repo root
set -e

XPR="$1"
if [ -z "$XPR" ]; then
  echo "[vivado-gui-launch] ERROR: no .xpr path given" >&2
  exit 1
fi

# Lightweight window manager so Vivado's dialogs/menus place and move correctly.
fluxbox >/tmp/fluxbox.log 2>&1 &

# Run from the project's build dir so stray Vivado files (vivado_pid*.str, .Xil)
# land under tmp/ instead of the repo root.
cd "$(dirname "$XPR")"
# Keep the journal (vivado.jou): GUI actions echo their Tcl there, and this dir
# is bind-mounted, so commands are readable/copyable on the host (the Xephyr
# window has no shared clipboard). -nolog still suppresses the noisier log.
exec vivado -nolog -mode gui "$(basename "$XPR")"
