#!/bin/bash
# One-time helper: copies the extracted PetaLinux sstate-cache and downloads
# archives (see the "PetaLinux offline build setup" section of
# docker_install.md) into a dedicated `petalinux-offline-cache` Docker
# volume. The petalinux service mounts this volume directly, so unlike the
# old host bind-mount approach, nothing about offline builds is
# host-specific anymore -- once this script has run, the source directories
# can be deleted.
#
# Usage:
#   ./petalinux-offline-cache.sh /path/to/downloads /path/to/arm-sstate-cache
#
# where the two paths are the `downloads` and `arm` directories extracted
# from the two AMD-provided archives (see docker_install.md).

set -e

DOWNLOADS_DIR="$1"
SSTATE_DIR="$2"

if [ -z "$DOWNLOADS_DIR" ] || [ ! -d "$DOWNLOADS_DIR" ] || [ -z "$SSTATE_DIR" ] || [ ! -d "$SSTATE_DIR" ]; then
    echo "Usage: $0 /path/to/downloads /path/to/arm-sstate-cache" >&2
    exit 1
fi

docker volume create petalinux-offline-cache >/dev/null

docker run -it --rm \
    -v petalinux-offline-cache:/cache \
    -v "$(realpath "$DOWNLOADS_DIR")":/src/downloads:ro \
    -v "$(realpath "$SSTATE_DIR")":/src/sstate-cache:ro \
    ubuntu:20.04 \
    bash -c "mkdir -p /cache/downloads /cache/sstate-cache && cp -a /src/downloads/. /cache/downloads/ && cp -a /src/sstate-cache/. /cache/sstate-cache/"

echo ""
echo "Offline cache copied into the 'petalinux-offline-cache' volume."
echo "You can now delete $DOWNLOADS_DIR and $SSTATE_DIR -- the volume"
echo "has its own independent copy, and OFFLINE=true will pick it up"
echo "automatically from here on."
