# Projects

This directory contains the structured source files to build individual projects. Each project is a Vivado project that can be built with the provided Makefile for certain configured boards. They also include the necessary configuration information for a PetaLinux OS to be built and loaded onto the board.

A project directory should follow the following structure:

```
[project_name]/
├── cfg/                                - Configuration files for the project
│   └── [board_name]/                   - Board-specific configuration files
│       ├── xdc/                        - Vivado XDC (Xilinx Design Constraint) files for the project.
│       │   └── [file_name].xdc         - XDC file for the project. Require .xdc extension.
│       │                                 These files define the hardware interface for the project and board.
│       │                                 They must include handling of the project's ports defined in ports.tcl.
│       └── petalinux/                  - PetaLinux configuration files for the project
│           │                             These files are patches to the default PetaLinux configuration.
│           │                             They can be created with the scripts in the scripts/ directory.
│           ├── config.patch            - Patch file for the PetaLinux project configuration
│           └── rootfs_config.patch     - Patch file for the PetaLinux filesystem configuration
├── modules/                            - [OPTIONAL] TCL scripts for block-design modules used in the project.
│   └── [module_name].tcl               - [OPTIONAL] TCL script for a module used in the block design
│                                         Modules are included using the "module" procedure, either in 
│                                         block_design.tcl or in another module script.
├── software/                           - [OPTIONAL] Software source files for the project (e.g. C, C++, Rust, Python)
├── block_design.tcl                    - TCL script that constructs the programmable logic for the project.
│                                         This script can use procedures defined in scripts/vivado/project.tcl
│                                         like `cell`, `module`, `init_ps` etc. to easily build the block design.
├── ports.tcl                           - TCL script that defines the ports for the project. This script should be  
│                                         the only place top-level block design ports are defined.
└── README.md                           - README file for the project, explaining the project's purpose and usage
```

## Programmable Logic (PL) Design

The main definition of the PL functionality is done in `block_design.tcl`. This script should use the procedures defined in `scripts/vivado/project.tcl` to build the block design (see the comments in that file, starting around line 50). The `ports.tcl` file defines the ports for the project, and should be the only place where top-level block design ports are defined.

*Syntax notes:* 
- *"Cell" and "core" are used somewhat interchangeably here, referring to objects in the block design*
- *A "module" in the block design is a sub-block of the design, treated as a cell when minimized*
- *In Vivado, a "pin" is a logical connection point on a cell. A "port" is a particular kind of pin that is at the top level, interfacing with the external physical I/O*
- *An "interface pin" is a collection of pins that are grouped together to form a single interface, like AXI or BRAM. These interfaces are Xilinx-defined*

## PetaLinux Processing System (PS) Configuration

The PetaLinux configuration files in `cfg/[board_name]/petalinux/` are patches to the default PetaLinux configuration for a given board and hardware definition file (xsa). They can be created with the `configure` scripts in the `scripts/petalinux` directory (see comments in those files for more info). The `config.patch` file is a patch file for the PetaLinux project configuration, and the `rootfs_config.patch` file is a patch file for the PetaLinux filesystem configuration.

