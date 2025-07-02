***Update 2025-06-27***
# `vivado` scripts

These scripts are for managing the Vivado build process. Vivado uses Tcl commands for all of its tasks and steps, which can be scripted and loaded, allowing for a fully automated build process. These scripts are used to create the Vivado project, build the block design, and package the bitstream and hardware definition into output files for PetaLinux to load. They are run by Vivado itself, passed in via the command line by the Makefile.

---

### `bitstream.tcl`

Arguments:
- `project_dir`: The temporary Vivado project directory (under `tmp/`) where the Vivado `project.xpr` file is located.
- `compress`: Whether to compress the bitstream file (default: `false`).

This script creates the Vivado bitstream `.bit` file. It checks for the existence of the Vivado project, runs implementation if needed, and generates a bitstream file. If `compress` is set to `true`, the bitstream is compressed and saved as `tmp/<project_dir>/compressed_bitstream.bit`; otherwise, it is saved as `tmp/<project_dir>/bitstream.bit`.

---

### `hw_def.tcl`

Arguments:
- `project_dir`: The temporary Vivado project directory (under `tmp/`) where the Vivado `project.xpr` file is located.

This script creates the Vivado `.xsa` hardware definition file. It checks for the existence of the Vivado project, runs implementation if needed, and generates a hardware definition `.xsa` file (including the bitstream) for use with PetaLinux. The output is written to `tmp/<project_dir>/hw_def.xsa`.

---

### `package_core.tcl`

Arguments:
- `vendor_name`: The name of the IP core vendor.
- `core_name`: The name of the IP core.
- `part_name`: The target FPGA part name.

This script packages a custom IP core for Vivado. It creates a new Vivado project for the specified core, adds the main source file and any submodules, and sets the top module. Vendor information is loaded from a JSON file to set display properties. The packaged core is saved under `tmp/custom_cores/<vendor_name>/<core_name>`, ready for use in Vivado projects.

---

### `project.tcl`

Arguments:
- `board_name`: The name of the target board.
- `board_ver`: The version of the target board.
- `project_name`: The name of the Vivado project.

This script is the bulk of the Vivado project setup and scripting. It creates and initializes the Vivado `project.xpr` project file in `tmp/`. It then sets up various convenient procedures that can be used for readability and simplicity in the project's `block_design.tcl` and submodule `modules/` script files. When understanding the `block_design.tcl` script, it is helpful to read through this file first to understand the defined procedures available.

---

### `repo_paths.tcl`

This script sets up the Vivado board repository paths for the Snickerdoodle Rev D project. It is sourced by Vivado's init script (see the **Vivado init script** section of the top-level README). It expects the `REV_D_DIR` environment variable to be set to the root of the repository (through `environment.sh` -- see the **Getting started** section of the top-level README) and loads the board files into Vivado's board repository.

---

### `utilization.tcl`

Arguments:
- `project_dir`: The temporary Vivado project directory (under `tmp/`) where the Vivado `project.xpr` file is located.

This script generates a hierarchical utilization report for the specified Vivado project. It checks for the existence of the project, ensures the reports directory exists, removes any previous utilization report, opens the project and synthesis run, and writes the hierarchical utilization report to `tmp_reports/<project_dir>/hierarchical_utilization.txt`.
