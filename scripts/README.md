# Scripts

A collection of scripts used in various parts of the automated build process. Some are run by the Makefile (or each other), others are run manually.

```
scripts/
├── make/                             - Scripts used as part of the Makefile
│   ├── get_cores_from_tcl.sh         - Script to extract used cores from a project's
│   │                                   "block_design.tcl", used in the Makefile
│   └── status.sh                     - Simple script to print nice status messages in the makefile log
├── petalinux/                        - Scripts used in building PetaLinux projects
│   ├── build.sh                      - Script to build the PetaLinux-loaded SD card files for the project
│   ├── config_project.sh             - Manual script to create new PetaLinux project configuration files
│   └── config_rootfs.sh              - Manual script to create new PetaLinux rootfs configuration files
├── software/                         - Scripts used in building software for the project
│   └── cross_compile.sh              - Manual script to cross compile C code for the ARM Cortex-A9
└── vivado/                           - Scripts used in building Vivado projects
    ├── bitstream.tcl                 - Script to build the bitstream from a Vivado .XPR project file,
    ├── hw_def.tcl                    - Script to generate the hardware definition file in Vivado
    ├── package_core.tcl              - Script to package a custom IP core for use in a
    │                                   Vivado block design, used in the Makefile
    ├── project.tcl                   - Script to build a Vivado .XPR project file, used in the Makefile
    └── repo_paths.tcl                - Script to set up Vivado environment variables for the repository
```
