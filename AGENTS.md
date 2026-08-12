# Zynq Toolbox — Copilot Instructions

## Overview
Build framework for Zynq-7000 SoC projects (AMD/Xilinx), producing bootable SD card images (FPGA bitstream + Linux kernel + rootfs). Primary project: **Rev D Shim Amplifier** (`projects/rev_d_shim/`), built on a general example-project framework.

Toolchain (Vivado + PetaLinux) runs on the host VM or in Docker, selected via `MODE` in `make_defaults.mk`.

Many folders have README.md files -- look at those for quick summaries of the material.

---

## ⚠️ Do Not Run Builds Unprompted
Never run `make` targets (`make`, `make sd`, `make bit`, `make xpr`, `make xsa`, `make petalinux`, `make petalinux_build`, `make cores`, `make clean_*`, etc.) unless the user explicitly asks in the current message. Builds are long, resource-intensive, and require large external tool installs — don't suggest or offer to run them.

Also, as a note, the temporary build files are in `tmp/` in this repo, NOT `/tmp/`. The `tmp/` folder is not tracked by git, so it can be messed with if desired.

## Build Commands
Setup: copy `make_defaults.mk.example` → `make_defaults.mk`, set `MODE`, `PROJECT`, `BOARD`, `BOARD_VER`.

```bash
make                          # Full SD build (default: rev_d_shim, snickerdoodle_black 1.0)
make PROJECT=ex01_basics BOARD=snickerdoodle_black BOARD_VER=1.0
make bit / xpr / xsa          # Bitstream / Vivado project / hardware def only
make petalinux / petalinux_build
make petalinux_cfg / petalinux_rootfs_cfg / petalinux_kernel_cfg   # GUI configs, need a large terminal
make clean_project / clean_build / clean_all
make write_sd [MOUNT_DIR=...] / make clean_sd [MOUNT_DIR=...]
make help                     # List all targets
```

### Tests
cocotb + Verilator, example available under `examples/cores/[vendor]/[core]/tests/src/testbench.py` (which some projects symlink to, replacing `examples` with the project path).

To run tests, examples:
```bash
./scripts/make/test_core.sh ex02_axi_interface base fifo_sync # single core
make tests PROJECT=rev_d_shim                                 # all tests for "rev_d_shim"
```
Output: `projects/[project]/cores/[vendor]/[core]/tests/test_status`, `projects/[project]/tests/core_tests_summary`. 

---

## Architecture

**Pipeline:** `cores → xpr → xsa → petalinux → sd`. Intermediates in `tmp/`; outputs in `out/[board]/[board_ver]/[project]/`.

**Project layout** (`projects/[name]/`):
| Path | Purpose |
|---|---|
| `block_design.tcl` | FPGA block design (Vivado Tcl) |
| `cfg/[board]/[board_ver]/xdc/` | Pin constraints |
| `cfg/.../petalinux/[ver]/config.patch` | PetaLinux system config patch |
| `cfg/.../petalinux/[ver]/rootfs_config.patch` | PetaLinux rootfs config patch |
| `modules/` | Reusable Tcl block-design sub-modules *(optional)* |
| `software/` | C software for rootfs *(optional)* |
| `kernel_modules/` | Out-of-tree kernel modules, each subdirectory built automatically *(optional)* |
| `rootfs_include/` | Files copied verbatim into rootfs `~` *(optional)* |
| `cores/` | Project-specific IP cores *(optional)* |

**Custom cores** — `projects/[project]/cores/[vendor]/[core]/` (some examples available in `examples/cores/[vendor]/[core]/`):
- `[core].v` — top module (name must match dir)
- `submodules/`, `tests/src/testbench.py`, `tests/src/parameters.json` *(all optional)*
- Vendor metadata in `[vendor]/vendor_info.json`

**Boards** — `boards/[board_name]/board_files/[board_ver]/`, lowercase snake_case, standard Vivado board files.

---

## Key Conventions

**`block_design.tcl` helpers** (`scripts/vivado/project.tcl`):
- `cell <vlnv> <name> {props} {connections}` — instantiate/connect IP (`vlnv` = `vendor:library:name:version`)
- `init_ps <name> {props} {connections}` — init Zynq PS from board preset
- `module <tcl_name> <instance> {connections}` — instantiate sub-module from `modules/[tcl_name].tcl`; use `create_bd_pin`, not `create_bd_port`
- `wire <pin1> <pin2>` — connect pins (regular or interface)
- `addr <offset> <range> <target_intf> <addr_space_intf>` — assign AXI address; **preferred over `auto_connect_axi`**
- `module_get_upvar <varname>` — pull a variable from the calling module's scope

**AXI naming**: subordinate ports prefixed `s_axi_` (e.g. `s_axi_awaddr`). BRAM ports need `(* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 ..." *)`.

**PetaLinux config = patch files**, not full configs (`config.patch`, `rootfs_config.patch`, relative to PetaLinux defaults, versioned under `cfg/[board]/[board_ver]/petalinux/[version]/`). Regenerate via `petalinux_cfg` / `petalinux_rootfs_cfg`.

**`make_defaults.mk`** is untracked (only `.example` is); same for `environment.sh` (VM mode only).

**Docker mode** (`MODE=container`): Makefile wraps `vivado`, `petalinux`, `cocotb` invocations via `docker compose run`. Repo is bind-mounted; outputs land on the host. `write_sd` must run on the **host**, not in-container.

**Offline builds**: `OFFLINE=true` uses the local PetaLinux download/sstate cache; container mode paths fixed via `PETALINUX_DOWNLOADS_PATH` / `PETALINUX_SSTATE_PATH`.
