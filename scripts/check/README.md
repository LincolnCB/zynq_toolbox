***Updated 2025-06-27***

# `check` scripts

These scripts are used to check required files, directories, and environment variables as part of the build process, giving the user feedback on what is missing or misconfigured.They're typically run by the Makefile or other scripts to ensure that the environment is set up correctly before proceeding with the build.

All of thesre scripts check for specific conditions for the step in question. They will also run a minimum set of previous checks required for the step to make sense, and can optionally run ALL previous checks if the `--full` flag is provided. The two exceptions are `board_files.sh` and `petalinux_offline.sh`, which do not have a `--full` option because they are not dependent on any previous checks.

---

### `board_files.sh`

Usage:
```bash
./scripts/check/board_files.sh <board_name> <board_version>
```
Check for the presence of board files of the given board and board version in the `boards/` directory.

---

### `project_dir.sh`
Usage:
```bash
./scripts/check/project_dir.sh <board_name> <board_version> <project_name> [--full]
```
Check for the existence of the project directory, block design Tcl file, configuration folders, and design constraints for the specified project, board, and version.

#### Minimum checks:
- None

#### `--full` check:
- [`board_files.sh`](#board_filessh)

---

### `project_src.sh`
Usage:
```bash
./scripts/check/project_src.sh <board_name> <board_version> <project_name> [--full]
```
Checks the project source scripts for the specified board, version, and project. Ensures that all referenced custom cores exist and have the required top-level Verilog file.

#### Minimum checks:
- [`project_dir.sh`](#project_dirsh)

#### `--full` check:
- [`project_dir.sh`](#project_dirsh) `--full`

---

### `xsa_file.sh`
Usage:
```bash
./scripts/check/xsa_file.sh <board_name> <board_version> <project_name> [--full]
```
Checks for the presence of the Vivado-generated XSA hardware definition file for the specified project, board, and version.

#### Minimum checks:
- None

#### `--full` check:
- [`project_src.sh`](#project_srcsh) `--full`

---

### `petalinux_env.sh`
Usage:
```bash
./scripts/check/petalinux_env.sh <board_name> <board_version> <project_name> [--full]
```
Check that the required PetaLinux environment variables are set and valid for the specified project, board, and version.

#### Minimum checks:
- None

#### `--full` check:
- [`xsa_file.sh`](#xsa_filesh) `--full`

---

### `petalinux_project.sh`
Usage:
```bash
./scripts/check/petalinux_project.sh <board_name> <board_version> <project_name> [--full]
```
Check for the existence of the PetaLinux project directory for the specified project, board, and version, and that it contains the required files.

#### Minimum checks:
- [`petalinux_env.sh`](#petalinux_envsh)

#### `--full` check:
- [`petalinux_env.sh`](#petalinux_envsh) `--full`

---

### `petalinux_cfg_dir.sh`
Usage:
```bash
./scripts/check/petalinux_cfg_dir.sh <board_name> <board_version> <project_name> [--full]
```
Check for the existence of the PetaLinux configuration directory for the specified project, board, and version.

#### Minimum checks:
- [`project_dir.sh`](#project_dirsh)
- [`petalinux_env.sh`](#petalinux_envsh)

#### `--full` check:
- [`petalinux_env.sh`](#petalinux_envsh) `--full`

---

### `petalinux_sys_cfg_file.sh`
Usage:
```bash
./scripts/check/petalinux_sys_cfg_file.sh <board_name> <board_version> <project_name> [--full]
```
Check for the presence of the PetaLinux system configuration patch file for the specified project, board, and version.

#### Minimum checks:
- [`petalinux_cfg_dir.sh`](#petalinux_cfg_dirsh)

#### `--full` check:
- [`petalinux_cfg_dir.sh`](#petalinux_cfg_dirsh) `--full`

---

### `petalinux_rootfs_cfg_file.sh`
Usage:
```bash
./scripts/check/petalinux_rootfs_cfg_file.sh <board_name> <board_version> <project_name> [--full]
```
Check for the presence of the PetaLinux root filesystem configuration patch file for the specified project, board, and version.

#### Minimum checks:
- [`petalinux_sys_cfg_file.sh`](#petalinux_sys_cfg_filesh)

#### `--full` check:
- [`petalinux_sys_cfg_file.sh`](#petalinux_sys_cfg_filesh) `--full`

---

### `petalinux_offline.sh`
Usage:
```bash
./scripts/check/petalinux_offline.sh
```
Check that the required PetaLinux offline directories (`downloads` and `sstate`) are set and exist.

#### Minimum checks:
- None

#### `--full` check:
- [`petalinux_project.sh`](#petalinux_projectsh) `--full`

---

### `kmod_src.sh`
Usage:
```bash
./scripts/check/kmod_src.sh <board_name> <board_version> <project_name> [--full]
```
Check for the validity of the `kernel_modules` file in the `projects/<project_name>/cfg/<board_name>/<board_version>/petalinux/` directory if it exists, which indicates which kernel modules should be built and included from the `kernel_modules/` directory.

#### Minimum checks:
- [`project_dir.sh`](#project_dirsh)
- [`petalinux_project.sh`](#petalinux_projectsh)

#### `--full` check:
- [`petalinux_project.sh`](#petalinux_projectsh) `--full`
