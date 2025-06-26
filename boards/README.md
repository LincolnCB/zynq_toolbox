# Board files

***TODO OUT OF DATE -- IN PROGRESS***

Board support can be added here by creating a folder named after the board. A board folder should follow the following structure:

```
[board_name]/
├── board_files/1.0/                      - Board files for the board
│   ├── board.xml                         - Board description file for Vivado
│   ├── part0_pins.xml                    - Pinout file for the board
│   └── preset.xml                        - Processing system preset file for the board
└── examples/                             - [OPTIONAL] Example or default design constraints
    │                                       and port definitions for the board
    ├── xdc/                              - [OPTIONAL] Example XDC files for the board, suffixed with .example
    │                                       (includes a ports.xdc.example defining the port design constraints)
    └── block_design.tcl                  - [OPTIONAL] Example block design ports for the board
                                            (matching the ports in xdc/ports.xdc.example)
```
Example files are just that, examples you can start from when manually adding board compatability to projects, and are not necessary for the board to be used in a project. They are just a nice reference.

To add a new board, create a new folder with the board's name (lowercase and underscores, a.k.a. snakecase). You will likely be able to find the board files online, which can be copied directly in. There will also likely be an example file with a `.xdc` extension, which can be used for the `examples/xdc` file. You may also find a `.tcl` file with the port definitions to be used as an `examples/block_design.tcl`, although you may create your own to define the block design interface with the XDC-defined ports in that example. 

To use a board for a project, you'll need to add its compatibility to the project's `cfg` directory. This will require creating a directory with the board's name, containing the necessary board-specific XDC files constraining the project's block design ports (which are defined in `block_design.tcl`) and PetaLinux configuration for the processing system. See the README in the `projects/` directory for more information.
