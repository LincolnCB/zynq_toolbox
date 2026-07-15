# docker/

Contains the containerized build environment for this repo:

- `Dockerfile`: the dev image (OS packages, non-root user, bash-as-default-shell). Does not contain the Xilinx tools themselves.
- `entrypoint.sh`: runs on every container start; wires up `ZYNQ_TOOLBOX`, `PETALINUX_PATH`, `VIVADO_PATH`, sources Vivado's `settings64.sh`, and generates `Vivado_init.tcl` automatically.
- `install-xilinx-tools.sh`: one-time helper that runs the real Xilinx GUI installer into the `xilinx-tools` Docker volume.
- `docker-compose.yml`: convenience wrapper around the `docker run` command used to start the dev container.

Full walkthrough, including installing Docker itself on Windows/macOS/Fedora/Ubuntu: see [the "Getting started" section of the top-level README](../README.md#getting-started).