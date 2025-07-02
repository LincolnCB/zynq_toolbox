***Updated 2025-07-02***
# Boards

This directory contains the necessary board files for any boards supported in this repo. These files are used by Vivado to build the hardware design used in creating the bitstream and PetaLinux OS. Currently, these boards all use a chip in the AMD/Xilinx Zynq-7000 series SoC family, primarily the Zynq-7020 and Zynq-7010. However, this should be extensible to the Zynq UltraScale+ MPSoC family as well with some configuration.

The files are organized by board name, and each board folder contains a `board_files` directory with the Vivado board files (per board version) that will be shared by the board distributors. The `board_files` directory can contain multiple versions of the board files if needed.

Each board folder also optionally contains an `examples` directory with suggested `.xdc` design constraint files (likely shared by the board distributor) and an example block design `.tcl` file that declares block design ports that match the ports defined in the `.xdc` files. These example files are not required for the board to be used in a project, but they can be helpful references when manually adding board compatibility to projects.

Board folders are named in lowercase and underscores (snakecase) to maintain consistency and ease of use. They are included in the Vivado path by the `scripts/vivado/repo_paths.tcl` script, which is sourced by the Vivado init Tcl script (see the **Profile setup** section in the main README for more information on the Vivado init script).

To add a new board, create a new folder with the board's name (lowercase and underscores, a.k.a. snakecase). You will likely be able to find the board files online, which can be copied directly in. There will also likely be an example file with a `.xdc` extension, which can be used for the `examples/xdc` file. You may also find a `.tcl` file with the port definitions to be used as an `examples/block_design.tcl`, although you may create your own to define the block design interface with the XDC-defined ports in that example. 

To use a board for a project, you'll need to add its compatibility to the project's `cfg` directory. This will require creating a directory with the board's name, containing the necessary board-specific XDC files constraining the project's block design ports (which are defined in `block_design.tcl`) and PetaLinux configuration for the processing system. See the README in the `projects/` directory for more information.
