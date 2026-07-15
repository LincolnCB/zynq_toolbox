#!/bin/bash
# One-time helper: runs the AMD/Xilinx unified installer GUI in a throwaway
# container, writing into the `xilinx-tools` Docker volume. Re-run this
# (twice -- once per product) the same way you would on a bare VM install.
#
# Usage:
#   ./install-xilinx-tools.sh /path/to/FPGAs_AdaptiveSoCs_Unified_2024.2_*.bin
#
# Requires an X server to display the installer GUI to. On Linux this
# script handles xhost for you. On macOS, install XQuartz first, enable
# "Allow connections from network clients" in its preferences, then export
# DISPLAY appropriately before running this script (see docker/README.md).
#
# Note: the installer .bin is bind-mounted read-write (not :ro) so the
# script can chmod +x it inside the container. This just sets the
# executable bit on your actual downloaded file on disk -- harmless, and
# it means the file stays executable for next time too.
#
# The throwaway container also installs a handful of X11 client libraries
# (libxext6, libxtst6, etc.) before launching the installer -- the base
# ubuntu:20.04 image doesn't include them, and the installer's Java/Swing
# GUI needs them to open a window even though it's just forwarding to your
# host's X server. It also generates the en_US.UTF-8 locale, since some of
# the installer's post-install scripts (e.g. PetaLinux's) call `setlocale`
# and otherwise print a "Pre/Post Installation Tasks Failed" warning dialog
# -- the underlying install still succeeds either way, but this avoids the
# scary-looking warning. It also installs python3 and symlinks it as
# `python`, since PetaLinux's post-install SDK setup script specifically
# calls `python` (not `python3`) and the bare image has neither -- unlike
# the locale warning, THIS one is not cosmetic: without it, the SDK setup
# step actually fails ("Error: The SDK needs a python installed"), leaving
# you with an incomplete PetaLinux install that will cause confusing
# failures later during `petalinux-create`/builds. Altogether this adds
# ~10-20 seconds the first time each product is installed.

set -e

INSTALLER_BIN="$1"
if [ -z "$INSTALLER_BIN" ] || [ ! -f "$INSTALLER_BIN" ]; then
    echo "Usage: $0 /path/to/FPGAs_AdaptiveSoCs_Unified_*.bin" >&2
    exit 1
fi

docker volume create xilinx-tools >/dev/null

if [ "$(uname)" = "Linux" ]; then
    xhost +local:docker >/dev/null
fi

docker run -it --rm \
    -e DISPLAY="$DISPLAY" \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v xilinx-tools:/tools/Xilinx \
    -v "$(realpath "$INSTALLER_BIN")":/tmp/installer.bin \
    --user root \
    ubuntu:20.04 \
    bash -c "apt-get update && apt-get install -y --no-install-recommends libxext6 libxtst6 libxi6 libxrender1 libsm6 libice6 fontconfig libfreetype6 locales python3 xz-utils xterm autoconf libtool texinfo zlib1g-dev gcc-multilib build-essential libncurses5-dev libtinfo5 less rsync bc lsb-release && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 && export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 && ln -sf /usr/bin/python3 /usr/bin/python && chmod +x /tmp/installer.bin && /tmp/installer.bin"

if [ "$(uname)" = "Linux" ]; then
    xhost -local:docker >/dev/null
fi

echo ""
echo "Installer closed. Run this script again with the same .bin file to"
echo "install the second product (PetaLinux and Vivado install separately,"
echo "same as the original VM instructions -- see docker/README.md)."
echo "Once both are installed, the 'xilinx-tools' volume contains everything"
echo "under /tools/Xilinx and can be mounted into as many dev containers as"
echo "you like without reinstalling."