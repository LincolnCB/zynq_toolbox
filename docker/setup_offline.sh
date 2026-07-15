#!/bin/bash
# Run as ZYNQ_MODE=offline (see docker-compose.yml's `offline` service).
# Extracts the two PetaLinux offline-build archives into whatever's mounted
# at /tools/petalinux_offline (the `zynq-petalinux-offline` volume). Each
# archive has a top-level directory (`downloads/`, `arm/`) which lands
# directly under the volume root -- `dev` mode's entrypoint.sh looks for
# exactly those two paths and wires up PETALINUX_DOWNLOADS_PATH /
# PETALINUX_SSTATE_PATH automatically, no extra flags needed at dev time.
#
# Usage (via compose, from repo root):
#   PETALINUX_DOWNLOADS_TAR=/path/to/downloads_2024.2_*.tar.gz \
#   PETALINUX_SSTATE_TAR=/path/to/sstate-cache_2024.2_*.tar.gz \
#     docker compose -f docker/docker-compose.yml run --rm offline

set -e

OFFLINE_ROOT="/tools/petalinux_offline"
mkdir -p "$OFFLINE_ROOT"

did_something=false

if [ -f /tmp/downloads.tar.gz ]; then
    echo "Extracting PetaLinux downloads cache..."
    tar -xzf /tmp/downloads.tar.gz -C "$OFFLINE_ROOT"
    did_something=true
fi

if [ -f /tmp/sstate.tar.gz ]; then
    echo "Extracting PetaLinux sstate-cache..."
    tar -xzf /tmp/sstate.tar.gz -C "$OFFLINE_ROOT"
    did_something=true
fi

if [ "$did_something" = false ]; then
    echo "ERROR: neither /tmp/downloads.tar.gz nor /tmp/sstate.tar.gz is mounted." >&2
    echo "       Set PETALINUX_DOWNLOADS_TAR and/or PETALINUX_SSTATE_TAR first." >&2
    exit 1
fi

chmod -R a+rX "$OFFLINE_ROOT"

echo ""
echo "Contents of $OFFLINE_ROOT:"
ls -la "$OFFLINE_ROOT"