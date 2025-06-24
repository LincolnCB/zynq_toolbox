# Projects

***TODO OUT OF DATE -- IN PROGRESS***

This directory contains the structured source files to build individual projects. Each project is a Vivado project that can be built with the provided Makefile for certain configured boards. They also include the necessary configuration information for a PetaLinux OS to be built and loaded onto the board.

A project directory should follow the following structure:

```
[project_name]/
├── cfg/                                - Configuration files for the project
│   └── [board_name]/[board_version]    - Board- and board-version-specific configuration files
│       ├── petalinux/[version]/        - PetaLinux configuration files for the project
│       │   │                               These files are patches to the default PetaLinux configuration.
│       │   │                               They can be created with the scripts in the scripts/petalinux directory.
│       │   │                               Multiple versions can be supported.
│       │   ├── config.patch            - Patch file for the PetaLinux project configuration
│       │   └── rootfs_config.patch     - Patch file for the PetaLinux filesystem configuration
│       └── xdc/                        - Vivado XDC (Xilinx Design Constraint) files for the project.
│           └── [file_name].xdc         - XDC file for the project. Require .xdc extension.
│                                           These files define the hardware interface for the project and board.
│                                           They must match the ports defined in the block design.
├── modules/                            - [OPTIONAL] TCL scripts for block-design modules used in the project.
│   └── [module_name].tcl               - [OPTIONAL] TCL script for a module used in the block design
│                                           Modules are included using the "module" procedure, either in 
│                                           block_design.tcl or in another module script.
├── rootfs_include/                     - [OPTIONAL] Files to be included in the PetaLinux root filesystem when built.
├── software/                           - [OPTIONAL] Software source files for the project (e.g. C, C++, Rust, Python).
├── block_design.tcl                    - TCL script that constructs the programmable logic for the project.
│                                           This script can use procedures defined in scripts/vivado/project.tcl
│                                           like `cell`, `module`, `init_ps` etc. to easily build the block design.
│                                           It includes any port definitions of the block design.
└── README.md                           - README file for the project, explaining the project's purpose and usage
```

## Programmable Logic (PL) Design

The main definition of the PL functionality is done in `block_design.tcl`, including the port defintion. This script should use the procedures defined in `scripts/vivado/project.tcl` to build the block design (see the comments in that file, starting around line 50).

*Syntax notes:* 
- *"Cell" and "core" are used somewhat interchangeably here, referring to objects in the block design*
- *A "module" in the block design is a sub-block of the design, treated as a cell when minimized*
- *In Vivado, a "pin" is a logical connection point on a cell. A "port" is a particular kind of pin that is at the top level, interfacing with the external physical I/O*
- *An "interface pin" is a collection of pins that are grouped together to form a single interface, like AXI or BRAM. These interfaces are Xilinx-defined*

## PetaLinux Processing System (PS) Configuration

The PetaLinux configuration files in `cfg/[board_name]/petalinux/` are patches to the default PetaLinux configuration for a given board and hardware definition file (xsa). They can be created with the `config` scripts in the `scripts/petalinux` directory (see comments in those files for more info). The `config.patch` file is a patch file for the PetaLinux project configuration, and the `rootfs_config.patch` file is a patch file for the PetaLinux filesystem configuration.

You may need to reconfigure PetaLinux projects if you're using a different version of PetaLinux. You can look at the patch files present in the `cfg/[board_name]/petalinux/` directory to see what changes are being made to the default configuration and reapply them manually with the `config` scripts `scripts/petalinux/config_project.sh` and `scripts/petalinux/config_rootfs.sh`.

