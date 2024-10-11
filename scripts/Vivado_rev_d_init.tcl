# Initialize the Vivado environment for the Snickerdoodle Rev D, declaring directories
# Source this from your Vivado_init.tcl
# Vivado_init.tcl is searched for in the following directories (in order, with each overwriting the previous):
# - Install directory (`/tools/Xilinx/Vivado/<version>/Vivado_init.tcl` by default)
# - Particular Vivado version (`~/.Xilinx/Vivado/<version>/Vivado_init.tc`)
# - Overall Vivado (`~/.Xilinx/Vivado/Vivado_init.tcl`)
set rev_d_dir $::env(REV_D_DIR)
set_param board.repoPaths [list ${rev_d_dir}/boards/snickerdoodle_black/brd/1.0/ ${rev_d_dir}/boards/stemlab_125_14/brd/1.1/ ${rev_d_dir}/boards/sdrlab_122_16/brd/1.0/ ]
