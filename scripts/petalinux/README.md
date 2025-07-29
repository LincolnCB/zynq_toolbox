***Updated 2025-06-27***
# `petalinux` Scripts

These scripts are for managing the PetaLinux build process. They are used to set up the PetaLinux config files, build the PetaLinux project, and package the necessary files for the SD card image. They are typically run by the Makefile or other scripts to ensure that the PetaLinux project is built correctly, but can also be run manually by the user if needed.

---

### `config_rootfs.sh`

Usage:
```bash
./scripts/petalinux/config_rootfs.sh <board_name> <board_version> <project_name>
```

This script creates or updates a patch file for the PetaLinux root filesystem configuration, storing only the non-default options in the git source code. It checks for required files, initializes a template project, applies any existing patches, and allows manual configuration of the root filesystem. The resulting patch is saved for project builds.

---

### `config_system.sh`

Usage:
```bash
./scripts/petalinux/config_system.sh <board_name> <board_version> <project_name>
```

This script creates or updates a patch file for the PetaLinux system configuration, storing only the non-default options in the git source code. It verifies prerequisites, initializes a template project, applies any existing configuration patch, and allows manual configuration of the system. The resulting patch is saved for project builds.

---

### `kernel_modules.sh`

Usage:
```bash
./scripts/petalinux/kernel_modules.sh <board_name> <board_version> <project_name>
```

Adds and configures kernel modules for the PetaLinux project. It reads a list of modules from the project and board's `kernel_modules`, creates the necessary recipes, and copies source files into the project for inclusion in the build.

---

### `make_offline.sh`

Usage:
```bash
./scripts/petalinux/make_offline.sh <petalinux_project_path
```

Configures the PetaLinux project for offline builds by updating configuration files to use local pre-mirror and sstate feeds, and disables network access for Yocto fetches.

---

### `package_boot.sh`

Usage:
```bash
./scripts/petalinux/package_boot.sh <board_name> <board_version> <project_name>
```

Packages the PetaLinux boot image, generating `BOOT.BIN` and related files. It uses the appropriate command for the PetaLinux version and creates a compressed archive containing the boot files.

---

### `package_rootfs_files.sh`

Usage:
```bash
./scripts/petalinux/package_rootfs_files.sh <board_name> <board_version> <project_name>
```

Packages additional project files into the PetaLinux root filesystem. It adds files from the project's `rootfs_include` directory into each user's home directory in the rootfs archive, overwriting existing files if necessary.

---

### `project.sh`

Usage:
```bash
./scripts/petalinux/project.sh <board_name> <board_version> <project_name>
```

Creates a new PetaLinux project for the specified board, version, and project, loading the hardware definition (`.xsa`) file and configuration patches, as well as running `make_offline.sh` and optionally including kernel configuration. It checks for required files, sets up the project directory, applies patches, and ensures the configuration matches the expected PetaLinux version.
