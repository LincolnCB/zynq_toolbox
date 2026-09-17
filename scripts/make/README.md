***Updated 2026-08-25***
# `make` scripts

These scripts are mainly used by the Makefile to perform various tasks related to the larger build process. The scripts are primarily shell scripts for processing and managing files safely, utilizing the `check/` scripts to give good error messages if something is missing or misconfigured. Some also extract some information from the source code to be used in the Makefile or other scripts, adding flexibility.

---

### `clean_sd.sh`

Usage:
```bash
./scripts/make/clean_sd.sh [<mount_directory>]
```

Clean the BOOT and RootFS directories on the mounted SD card. If no mount directory is provided, it will default to `/media/[username]/`. Requires `sudo` for file operations. Used by the Makefile in the `clean_sd` target.

---

### `cocotb.mk`

This is a Makefile used to build the cocotb testbench for custom verilog cores. It's used with [`test_core.sh`](#test_coresh) to build the testbench and run the tests, interfacing with the `cocotb` Python library and its respective Makefiles. It's included by `test_core.sh` rather than run on its own, and it shells out to `cocotb-config`, so `cocotb` has to be on PATH -- true on a **VM** host or inside the cocotb container, but not on a **Docker** host. You can read more about running tests in the [top level](../../README.md#testing) and [`examples/cores/`](../../examples/cores/README.md) README files.

---

### `cross_compile.sh`

Usage:
```bash
./scripts/make/cross_compile.sh <source_file> <output_file>
```

This is a slightly vestigial script that can be used manually to cross-compile a C/C++ program for the Zynq ARM architecture. It uses the `arm-linux-gnueabihf-gcc` compiler included with the AMD/Xilinx tools. This should be run by the user directly if needed. Software for PetaLinux projects can be build automatically in the build process (see READMEs for `projects/` and `scripts/petalinux/`, particularly the script `scripts/petalinux/software.sh`).

---

### `get_board_part.sh`

Usage:
```bash
./scripts/make/get_board_part.sh <board_name> <board_version>
```

Extracts the vendor, board name, component name, and file version from the XML file for a given board and version. Outputs the information in the format:
`<vendor>:<name>:<component>:<file_version>`

Returns a nonzero exit code if any information is missing or the XML file does not exist. Used by the Makefile and `scripts/vivado/` scripts to determine the necessary board information for the Vivado project from the board files in `boards/`.

---

### `get_cores_from_tcl.sh`

Usage:
```bash
./scripts/make/get_cores_from_tcl.sh <block_design.tcl>
```

Parses a Tcl block design file (including submodules under `modules/` in the same project directory as the given file) to extract the paths of custom cores instantiated with the `cell` procedure (see `scripts/vivado/project.tcl`). Recursively processes modules included with the `module` procedure. Outputs a deduplicated, sorted list of custom core paths. If two cores have the same name (basename), the script prints an error and exits. Used by the Makefile to determine the custom cores needed by a project.

---

### `get_part.sh`

Usage:
```bash
./scripts/make/get_part.sh <board_name> <board_version>
```

Extracts the FPGA part name from the XML file for the specified board and version. Outputs only the part name string. Returns a nonzero exit code if the XML file does not exist or the part name is missing. Used by the Makefile and Vivado scripts to determine the correct FPGA part for synthesis and implementation.

---

### `status.sh`

Usage:
```bash
./scripts/make/status.sh <status_string>
```

Formats and prints a status string with separators for improved readability in Makefile logs. Expects a single status string argument. Prints an error and exits if no argument is provided.

---

### `test_core.sh`

Usage:
```bash
./scripts/make/test_core.sh <project> <vendor> <core>
```

Runs cocotb-based tests for a custom core located in `projects/<project>/cores/<vendor>/<core>/tests`. Uses the shared `cocotb.mk` Makefile to build and run the testbench. Writes test results and status to the appropriate files in the core's test directory. Exits with a nonzero code if the tests fail or if required directories are missing.

This runs cocotb/Verilator directly, so it needs those tools on PATH. Call it standalone only in **VM** mode; in **Docker** mode (`MODE=container`) `cocotb` lives only inside the cocotb container, so a bare host call fails with `cocotb-config: No such file or directory`. Drive it through the make targets there -- `make tests` for all of a project's cores, or a per-core `test_status` target (e.g. `make projects/rev_d_shim/cores/shim/datapath_mux/tests/test_status PROJECT=rev_d_shim`) for one -- which wrap this script in the container via the Makefile's `run_cocotb`.

The run is bounded by a wall-clock timeout so a hung simulation (a testbench that parks the DUT and never returns) self-terminates rather than blocking the suite. The default is 600 seconds per core; override it with the `CORE_TEST_TIMEOUT` environment variable (and `CORE_TEST_KILL_GRACE`, the seconds to wait after `SIGTERM` before escalating to `SIGKILL` for a child that ignores it). On expiry the core's status is recorded as `TIMED OUT`. An interrupt (Ctrl-C) or `SIGTERM` is relayed to the test process and recorded as `ABORTED`, so pressing Ctrl-C during `make tests` stops the run cleanly; under `docker compose run --rm` container teardown then reaps anything the simulator left behind. In container mode (`MODE=container`) the two variables are passed through to the cocotb container by `scripts/docker/docker-compose.yml`, so `CORE_TEST_TIMEOUT=1200 make tests` works from the host.

---

### `write_sd.sh`

Usage:
```bash
./scripts/make/write_sd.sh <board_name> <board_version> <project_name> [<mount_directory>]
```

Writes the BOOT and RootFS images for a given board and project to a mounted SD card. Checks for required output files and mount directories, then extracts the images to the appropriate locations on the SD card. Requires `sudo` for file operations. Used after building a project to prepare an SD card for deployment, or by the Makefile to automate the process.
