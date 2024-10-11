# Board files

Board support can be added here by creating a folder named after the board. The folder should contain the following files and directories:

- `board_files/1.0/`: This directory should contain the board files.
- `default_xdc/`: This directory should contain any XDC files that the board would use by default -- for example, the default pinout for the board.
- `board_config.json`: This file contains configuration information for the Makefile and TCL scripts (`project.tcl` in particular). The JSON file should contain the following fields:
  - `part`: The part number of the SoC used on the board (e.g. `xc7z020clg400-1` or `xc7z010clg400-1`).
  - `proc`: The processor used on the SoC (e.g. `ps7_cortexa9_0`).
  - `board_part`: The Vivado string identifying the board part (e.g. `redpitaya.com:stemlab_125_14:part0:1.0` or `krtkl.com:snickerdoodle_black:part0:1.0`).
- `default_ports.tcl`: This file should contain the default block design ports for the board. This should match with the default pinout XDC in `default_xdc/`.
