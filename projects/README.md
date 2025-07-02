***Updated 2025-06-30***
# Projects

This directory contains the structured source files to build individual projects. Each project has its own folder, and is mainly defined by its `block_design.tcl` file, which defines the FPGA system's block design. Each project will also need folders under `cfg` that define the compatibility with different boards, and can have a few other special folders that augment the build process. To use `make` to build a project, you will need to do it from the top level directory, specifying the project name and the board name and version, like so:

```bash
make PROJECT=[project_name] BOARD=[board_name] VERSION=[board_version] [target]
```
See the **Building a different board, board version, or project** and **Intermediate build files and targets** targets in the top-level README for more information.

## `block_design.tcl`

This is the main file that defines the programmable logic (PL) design for the project. It constructs the Vivado block design using Tcl commands. It also handles port definitions and can include other Tcl "modules" from the `modules/` directory. 

For Tcl commands, you can use any Vivado procedures directly, or use helper procedures defined in `scripts/vivado/project.tcl`. These helper procedures simplify the process of creating cells and modules, assigning AXI addresses, and initializing the processing system (PS). See the below section [`scripts/vivado/project.tcl` procedures](#scriptsvivadoprojecttcl-procedures) for more information on the available procedures, or look at the comments in `scripts/vivado/project.tcl` directly.

If you're exploring development, one useful approach is to try things out in Vivado's GUI -- when doing anything in the Vivado GUI, it will print the equivalent Tcl commands in the console near the bottom. You can then copy those commands into any Tcl scripts, such as the `block_design.tcl` file or those in `modules/`. To create just the Vivado project for a project, which is useful for testing as above, you can use the intermediate `make` target `xpr`, which will create the Vivado project file (`.xpr`) without building any of the following steps. You can then open the project from `tmp/[board_name]/[board_version]/[project_name]/project.xpr` in Vivado and explore the block design.

### `scripts/vivado/project.tcl` procedures

#### `wire` 

Arguments:
- `name1`: The name of the first pin to wire.
- `name2`: The name of the second pin to wire.

Procedure for connecting (wiring) two pins together by name. Can handle both regular and interface pins (Xilinx-defined groups of pins that define an interface, like AXI or a BRAM port). Attempts to wire the given names as normal pins, then re-attempts as interface pins.

Example usage:
```tcl
wire my_module/s_axi ps/M_AXI_GP0
```
This will wire the `my_module/s_axi` interface pin to the `ps/M_AXI_GP0` interface pin.

#### `addr`

Arguments:
- `offset`: offset of the address
- `range`: range of the address
- `target_intf_pin`: name of the interface pin which will be assigned an address
- `addr_space_intf_pin`: name of the pin containing the address space

Procedure for assigning an address for a connected AXI interface pin (`target_intf_pin`) in an address space defined by another interface pin (`addr_space_intf_pin`). The address is defined by the `offset` and `range` arguments. 

Example usage:
```tcl
addr 0x40000000 128 my_module/s_axi ps/M_AXI_GP0
```
This would assign an address of `0x40000000` with a range of `128` to an AXI interface pin `my_module/s_axi` connected through interconnects to the interface pin `ps/M_AXI_GP0` at the top.

#### `auto_connect_axi`

Arguments:
- `offset`: Offset of the address to assign to the connected AXI interface.
- `range`: Address range for the interface.
- `intf_pin`: Name of the interface pin to connect to the AXI interconnect.
- `master`: Name of the master interface to connect (should be an absolute path, e.g., `/ps/M_AXI_GP0`).

This procedure automates the creation and connection of an AXI interconnect between a master and a slave interface. It applies Vivado's AXI automation to connect the specified interface pin to the master, then assigns the address space using the provided offset and range.Projects in this repo preffer to manually connect AXI interfaces with interconnects and use the `addr` procedure to assign addresses for clarity and certainty, but this procedure is included as an alternative.

Example usage:
```tcl
auto_connect_axi 0x40000000 128 my_module/s_axi /ps/M_AXI_GP0
```
This will connect `my_module/s_axi` to the master interface `/ps/M_AXI_GP0` and assign it the address range `128` at offset `0x40000000`.

#### `cell`

Arguments:
- `cell_vlnv`: VLNV (Vendor:Library:Name:Version) identifier of the core/cell to instantiate.
- `cell_name`: Name to assign to the created cell.
- `cell_props`: List of key-value pairs of properties to set on the cell (can be empty).
- `cell_conn`: List of key-value pairs of pin connections, mapping local pin names to remote pin names (can be empty).

Creates a new cell in the block design, sets its properties, and wires its pins to other design elements as specified. This simplifies instantiating and connecting IP blocks or modules. The `cell_vlnv` should be a string in the format `vendor:library:name:version`, where `vendor:library` is the IP vendor and library type (e.g., `xilinx.com:ip` or `lcb:user`), `name` is the name of the core, and `version` is the version of the core (optional in some cases). The `cell_props` argument is list of key-value pairs that set properties on the cell as defined by the Xilinx IP core or the `parameters` of the Verilog core (for custom cores). The `cell_conn` argument is a list of key-value pairs that define the connections for the cell's pins -- this uses the `wire` procedure to connect the pins, but the key names in the dictionary are the local pin names, and do not need to be prefixed with the cell name or path.

Please note that while the `cell_props` and `cell_conn` lists can be empty or span multiple lines between the braces, the command itself should not have line breaks in it (outside of the braces). Read up on [Tcl quote syntax](https://wiki.tcl-lang.org/page/Practical_Advice_on_Quotes_and_Brackets_in_TCL) if you start having issues with this or want to understand it better.

Example usage:
```tcl
cell xilinx.com:ip:xlconcat:2.1 sts_concat {
  NUM_PORTS 3
} {
  In0 hw_manager/status_word
  In1 axi_spi_interface/fifo_sts
  In2 pad_160/dout
  dout status_reg/sts_data
}
```
or
```tcl
cell lcb:user:shim_axi_prestart_cfg axi_prestart_cfg {
  INTEGRATOR_THRESHOLD_AVERAGE_DEFAULT 16384
  INTEGRATOR_WINDOW_DEFAULT 5000000
  INTEG_EN_DEFAULT 1
} {
  aclk ps/FCLK_CLK0
  aresetn ps_rst/peripheral_aresetn
  S_AXI ps_periph_axi_intercon/M00_AXI
}
```

#### `init_ps`

Arguments:
- `ps_name`: Name to assign to the processing system cell.
- `ps_props`: List of key-value pairs of properties to set on the PS (can be empty).
- `ps_conn`: List of key-value pairs of pin connections, mapping local pin names to remote pin names (can be empty).

Initializes the processing system (e.g., Zynq PS) using the board preset (`preset.xml` in the `board_files/` of the board under the `boards/` directory). You can overwrite the default properties from the preset file with the `ps_props` argument, as with the `cell` procedure's `cell_props` argument. The `ps_conn` argument works the same as the `cell_conn` argument of the `cell` procedure above.

Example usage:
```tcl
init_ps ps {
  PCW_USE_S_AXI_ACP 0
} {
  M_AXI_GP0_ACLK ps/FCLK_CLK0
}
```

#### `module`

Arguments:
- `module_src`: Name of the Tcl source file (without `.tcl`) to include as a module.
- `module_name`: Name to assign to the module instance.
- `module_conn`: List of key-value pairs of pin connections, mapping local pin names to remote pin names (can be empty).

Instantiates a block design module from a Tcl script in the `modules/` directory of the current project. The `module_src` argument is the name of the Tcl script to include, without the `.tcl` extension (e.g., in the project `my_project`, if you have a file `projects/my_project/modules/my_module.tcl`, you can use `my_module` as the `module_src` argument for any `module` calls in the `block_design.tcl` file OR in other modules in the project). The `module_conn` argument works the same as the `cell_conn` argument of the `cell` procedure above -- note that local pins with no prefix will need to be declared as `bd_pin`s in the module script.

Example usage:
```tcl
module fifo axi_fifo_module {
  aclk ps/FCLK_CLK0
  cfg_word axi_fifo_cfg/dout
  s_axi axi_smc/M02_AXI
}
```
This will include the `modules/fifo.tcl` script and name the instance `axi_fifo_module`, connecting the `axi_fifo_module/aclk` pin to the `ps/FCLK_CLK0` pin etc.

#### `module_get_upvar`

Arguments:
- `varname`: Name of the variable to retrieve from the calling context.

Retrieves the value of a variable from the parent context (the Tcl script that called the `module` proc) when inside a module. This is useful for passing variables into module scripts.

Example usage:
```tcl
set my_val [module_get_upvar my_var]
```


## `cfg/` directory

This directory contains the project's configuration files for different boards and board versions. Each board and version has its own subdirectory, formatted as `cfg/[board_name]/[board_version]/`. Filling out this directory with the following files defines compatability between the project and given board/version. The necessary files are are the following subdirectories and their contents:

### `petalinux/[petalinux_version]/`
This directory contains the PetaLinux configuration files for the project. These files are loaded as part of the PetaLinux build process, particularly by scripts in the `scripts/petalinux` directory. PetaLinux's configuration files are slightly more version-sensitive than Vivado, and so need to be configured for each version. The files are:

#### `config.patch`
A patch file for the PetaLinux project configuration. This file contains changes to the default PetaLinux configuration for the project's system. It's stored in a patch format both for density and clarity -- it's much easier to see what options need to be changed from the default to make everything work than it is to parse the fairly large configuration files. 

If you want to make or update this file, you can run `make` in the top-level directory with the `petalinux_cfg` target (with the `PROJECT`, `BOARD`, and `VERSION` variables set to the appropriate values). If you're using a different version of PetaLinux than is currently supported, the recommended approach to create your own configuration file is to use the above `make petalinux_cfg` approach to manually set the listed non-default options read directly from the text of another version's `config.patch` file 

For example, to create a new `config.patch` file for your computer's PetaLinux 2023.2, you would open 
```
projects/[project_name]/cfg/[board_name]/[board_version]/petalinux/2024.2/config.patch
```
for reference, then run (with a sufficiently large terminal window for the GUI -- the script will tell you if the terminal is too small):
```bash
make PROJECT=[project_name] BOARD=[board_name] VERSION=[board_version] petalinux_cfg
```
and manually look through the `2024.2` version as a guide to set the equivalent options in the `2023.2` version.

#### `rootfs_config.patch`
A patch file for the PetaLinux filesystem configuration. Similar to the `config.patch` file, this file contains changes to the default PetaLinux filesystem configuration for the project's system. It can be created or edited with the `make petalinux_rootfs_cfg` target in the top-level directory. Follow the same advice as above for creating a new version of this file.

#### `kernel_modules` (**OPTIONAL**)
A simple text file that lists the kernel modules that should be included in the PetaLinux build. This is used by the `scripts/petalinux/kernel_modules.sh` script to automatically include the specified custom kernel modules from the top-level directory `kernel_modules/` in your PetaLinux build. This file is optional, and if it is not present, no custom kernel modules will be included in the PetaLinux build.

### `xdc/`

This directory contains any Xilinx Design Constraints (XDC) files for the project. These files define the hardware interface for the project and board (primarily pin assignments and types), and must match the ports defined in the block design. When building a project, any file in this directory with the `.xdc` extension will be included in the Vivado project. Often, a default or example `.xdc` file is provided with the the board files (see the `boards/` README for more detail). For boards already supported in this repo, there are some examples in that directory.

## Additional directories (OPTIONAL)

### `modules/`

This directory contains Tcl scripts for block-design modules used in the project. These modules are reusable components that can be included in the block design using the `module` procedure, either in `block_design.tcl` or in another module script. They behave almost identically to the `block_design.tcl` file, but should set `bd_pin`s (block design module pins) with the `create_bd_pin` Tcl procedure instead of `bd_port`s (block design ports, interfacing with the external physical I/O) with the `create_bd_port` Tcl procedure like `block_design.tcl` does -- modules are not at the top level of the block design, and should not be interfacing with the external physical I/O.

Any `.tcl` file in this directory will be included in the Vivado project. The `module` Tcl procedure is defined in `scripts/vivado/project.tcl`.

### `rootfs_include/`

This directory simply contains files to be included in the PetaLinux root filesystem when built. The contents of this directory will be copied directly into the PetaLinux root filesystem `~` directory when the PetaLinux project is built.

### `software/`

This directory contains C code for software that will be automatically compiled and included in the PetaLinux build. Each folder will be built to a binary of the same name. The top C file should be named `[software_name].c`, where `[software_name]` is the name of the software (same name as the folder). Other `.c` files can be included in the same folder, and will be compiled together with the top-level file. The software binaries will be built as part of the PetaLinux build process, and will be included in the root filesystem.

### `tests/`

This folder will be created if you run tests for the project using the `make tests` target in the top-level directory. It will contain the results of the tests run for the project concatenated as `core_tests_summary`.

## Main projects

Please read the README in each of the main project directories for more information on the project, but in brief, the main projects in this repo are:

### `rev_d_shim/`
This is the main project for the Rev D Shim firmware. It contains the block design for the Rev D Shim, as well as the PetaLinux configuration files and software for the project.

### `shim_controller_v0/`

This is the beta version of the Rev D Shim firmware, written almost entirely by Thomas Witzel. It's included in this repo as both a baseline backup as well as a verification for the build process of the repo.

## Example projects

To understand the build processes in this repo, it's recommended to explore the example projects in this directory. Each project has its own folder, and the example projects are prefixed with `ex##_`, where `##` is the example number. They're ordered to progressively build up the scripting and configuration concepts I personally needed to learn to build the Rev D Shim firmware, so they should be a good starting point for understanding how to build your own projects. 

You should read through the README in each of their respective folders, but in brief, the example projects are:

### EX01 -- Basics

This example project is mostly a template for the minimum viable project. It will walk you through the basic steps that any project will use, explaining the fundamental Vivado and PetaLinux build steps, including how to incorporate basic software or files in the built SD card. This is necessary to build the Rev D Shim PS and PL components.

### EX02 -- AXI interface

This example project explores more of the Vivado Tcl scripting capabilities and demonstrates the basic AXI interface, which will be how the Zynq's CPU / processing system (PS) communicates with the FPGA / programmable logic (PL). It includes some playground software to try out various AXI interfaces. This is necessary for the Rev D Shim firmware to actually control the hardware, as it needs to communicate with the FPGA to set the shim channels and read the buffer data (among other things).

### EX03 -- UART

This example project demonstrates some configuration options for the PS's interfaces, including its UART interface. It's a good overview of how to connect the Zynq's PS to an external computer via a UART interface. This is necessary for the Rev D Shim firmware to communicate with an external host computer outside of the scanner room.

### EX04 -- Interrupts

This example project covers interrupts from the PL to the PS and software to handle that, allowing the PL to signal the PS when it needs attention. This is necessary for the safety features of the Rev D Shim firmware.

### EX05 -- DMA

This example project covers the Direct Memory Access (DMA) interface, which allows the PS to transfer data to and from the PL through the off-chip DDR memory.
