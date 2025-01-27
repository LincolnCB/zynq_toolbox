# Board files

Board support can be added here by creating a folder named after the board. A board folder should follow the following structure (all of these files except for board_config.json and ports.tcl.example will be available for download somewhere for other boards. Example files are just that, examples you can start from when manually adding board compatability to projects, and are not necessary for the board to be used in a project):

```
[board_name]/
├── board_files/1.0/                      - Board files for the board
│   ├── board.xml                         - Board description file for Vivado
│   ├── part0_pins.xml                    - Pinout file for the board
│   └── preset.xml                        - Processing system preset file for the board
├── examples/                             - [OPTIONAL] Example or default design constraints
│   │                                       and port definitions for the board
│   ├── xdc/                              - [OPTIONAL] Example XDC files for the board, suffixed with .example
│   │                                       (includes a ports.xdc.example defining the port design constraints)
│   └── ports.tcl.example                 - [OPTIONAL] Example block design ports for the board
│                                           (matching the ports in xdc/ports.xdc.example)
└── board_config.json                     - Configuration information for Vivado that covers the SoC and board parts
```

To add a new board, you should have all the files except for `board_config.json` and `ports.tcl.example`. The example `ports.tcl.example` can be constructed to match an existing example `ports.xdc` or some equivalent XDC file for the board. The `board_config.json` file should contain the following information:

```json
{
    "part": "[FPGA part, e.g. xc7z020clg400-1]",
    "proc": "[Processor part, e.g. ps7_cortexa9_0]",
    "board_part": "[distributor.domain:name:part0:1.0, e.g. redpitaya.com:sdrlab_122_16:part0:1.0]"
}
```

To use a board for a project, you'll need to add its compatibility to the project's `cfg` directory. This will require creating a directory with the board's name, containing the necessary board-specific XDC files constraining the project's ports (which are defined in `ports.tcl`) and PetaLinux configuration for the processing system. See the README in the `projects/` directory for more information.

The current boards are:
- `snickerdoodle_black` - The Snickerdoodle Black, the target board for the Rev D Shim
- `stemlab_125_14` - The Red Pitaya STEMlab 125-14, used in many of Pavel Demin's projects
- `sdrlab_122_16` - The Red Pitaya SDRLab 122-16, which the OCRA project supports
- `zybo_z7_10` - The Digilent Zybo Z7-10, which uses the Zynq-7010 SoC
