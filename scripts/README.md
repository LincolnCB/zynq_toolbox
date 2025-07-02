# Scripts

***Updated 2025-06-27***

A collection of scripts used in various parts of the automated build process. Some are run by the Makefile (or each other), others are run manually by the user. Scripts are divided into general categories.

## `check/`

These scripts are used to check required files, directories, and environment variables as part of the build process, giving the user feedback on what is missing or misconfigured.They're typically run by the Makefile or other scripts to ensure that the environment is set up correctly before proceeding with the build.

All of thesre scripts check for specific conditions for the step in question. They will also run a minimum set of previous checks required for the step to make sense, and can optionally run ALL previous checks if the `--full` flag is provided. The one exception is `board_files.sh`, which does not have a `--full` option because it is not dependent on any previous checks.

You can read the documentation for each script in the `scripts/check/` README.

## `make/`

These scripts are mainly used by the Makefile to perform various tasks related to the larger build process. The scripts are primarily shell scripts for processing and managing files safely, utlizing the `check/` scripts to give good error messages if something is missing or misconfigured. Some also extract some information from the source code to be used in the Makefile or other scripts, adding flexibility.

You can read the documentation for each script in the `scripts/make/` README.

## `petalinux/`

These scripts are for managing the PetaLinux build process. They are used to set up the PetaLinux config files, build the PetaLinux project, and package the necessary files for the SD card image. They are typically run by the Makefile or other scripts to ensure that the PetaLinux project is built correctly, but can also be run manually by the user if needed.

You can read the documentation for each script in the `scripts/petalinux/` README.

## `vivado/`

These scripts are for managing the Vivado build process. Vivado uses Tcl commands for all of its tasks and steps, which can be scripted and loaded, allowing for a fully automated build process. These scripts are used to create the Vivado project, build the block design, and package the bitstream and hardware definition into output files for PetaLinux to load. They are run by Vivado itself, passed in via the command line by the Makefile.

You can read the documentation for each script in the `scripts/vivado/` README.
