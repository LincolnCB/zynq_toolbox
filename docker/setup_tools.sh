#!/bin/bash
# Run as ZYNQ_MODE=tools (see docker-compose.yml's `tools` service). Installs
# into whatever's mounted at /tools/Xilinx (the `zynq-tools` volume) -- runs
# as root since a freshly created volume starts out root-owned; each branch
# chmods its own output to world-readable/executable so the non-root
# `builder` user can use it later in `dev` mode.
#
# Usage (via compose, from repo root):
#   INSTALLER_BIN=/path/to/FPGAs_AdaptiveSoCs_Unified_2024.2_*.bin \
#     docker compose -f docker/docker-compose.yml run --rm tools xilinx
#   docker compose -f docker/docker-compose.yml run --rm tools cocotb
#   docker compose -f docker/docker-compose.yml run --rm tools verilator [tag]

set -e

TOOLS_ROOT="/tools/Xilinx"
SUBCOMMAND="$1"
shift || true

case "$SUBCOMMAND" in

  xilinx)
    # Same interactive GUI installer as the old install-xilinx-tools.sh --
    # run this once per product (PetaLinux, then Vivado), same as the VM
    # path. See docker/README.md for the product/edition selections to make.
    if [ ! -f /tmp/installer.bin ]; then
        echo "ERROR: no installer .bin mounted at /tmp/installer.bin." >&2
        echo "       Set INSTALLER_BIN=/path/to/installer.bin before running." >&2
        exit 1
    fi
    chmod +x /tmp/installer.bin
    /tmp/installer.bin
    echo ""
    echo "Installer closed. If you haven't installed both products yet,"
    echo "re-run this command for the other one (PetaLinux and Vivado"
    echo "install separately). See docker/README.md."
    ;;

  cocotb)
    mkdir -p "$TOOLS_ROOT/cocotb"
    PYTHONUSERBASE="$TOOLS_ROOT/cocotb" pip3 install --user cocotb cocotb_coverage
    chmod -R a+rX "$TOOLS_ROOT/cocotb"
    echo "cocotb installed into $TOOLS_ROOT/cocotb"
    ;;

  verilator)
    VERSION="${1:-stable}"
    BUILD_DIR="/tmp/verilator-build"
    INSTALL_DIR="$TOOLS_ROOT/verilator"

    rm -rf "$BUILD_DIR"
    git clone https://github.com/verilator/verilator "$BUILD_DIR"
    cd "$BUILD_DIR"
    git checkout "$VERSION"
    unset VERILATOR_ROOT
    autoconf
    ./configure --prefix="$INSTALL_DIR"
    make -j"$(nproc)"
    make install
    chmod -R a+rX "$INSTALL_DIR"
    rm -rf "$BUILD_DIR"
    echo "Verilator ($VERSION) installed into $INSTALL_DIR"
    ;;

  *)
    echo "Usage: $0 {xilinx|cocotb|verilator} [args]" >&2
    exit 1
    ;;
esac