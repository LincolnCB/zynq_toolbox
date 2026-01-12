# Initialize the Vivado environment for the Snickerdoodle Rev D, declaring directories

# Source this from your Vivado_init.tcl. 
# Make sure to set the ZYNQ_TOOLBOX environment variable to the root of the this repository.
# Example (to paste into Vivado_init.tcl):
# ------------------------------------------------------------
#     # Set up Rev D configuration
#     set zynq_toolbox $::env(ZYNQ_TOOLBOX)
#     source $zynq_toolbox/scripts/vivado/repo_paths.tcl
# ------------------------------------------------------------

# Vivado_init.tcl is searched for by Vivado in the following directories (in order, with each overwriting the previous):
# - Install directory (`/tools/Xilinx/Vivado/<version>/Vivado_init.tcl` by default)
# - Particular Vivado version (`~/.Xilinx/Vivado/<version>/Vivado_init.tc`)
# - [Developer choice] Overall Vivado (`~/.Xilinx/Vivado/Vivado_init.tcl`)

set zynq_toolbox $::env(ZYNQ_TOOLBOX)
set_param board.repoPaths [glob -type d ${zynq_toolbox}/boards/*/board_files/*/]
