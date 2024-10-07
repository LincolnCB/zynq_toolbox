
package require fileutil
package require json

# Arguments: project_name part_name core_vendor_list
set project_name [lindex $argv 0]
set board_name [lindex $argv 1]
set core_vendor_list [lindex $argv 2]

# Read the config for the board for scripting variables
if {[file exists boards/${board_name}/board_config.json]} {
    set board_config_fd [open boards/${board_name}/board_config.json "r"]
} else {
    error "Board configuration file boards/${board_name}/board_config.json does not exist.\nThe board \"${board_name}\" may not be supported for this project."
}
set board_config_str [read $board_config_fd]
close $board_config_fd
set board_config_dict [json::json2dict $board_config_str]

# Get the part name from the config dict
set part_name [dict get $board_config_dict HDL part]
set board_part [dict get $board_config_dict HDL board_part]

# Clear out old build files
file delete -force tmp/${board_name}_${project_name}.cache tmp/${board_name}_${project_name}.gen tmp/${board_name}_${project_name}.hw tmp/${board_name}_${project_name}.ip_user_files tmp/${board_name}_${project_name}.runs tmp/${board_name}_${project_name}.sim tmp/${board_name}_${project_name}.srcs tmp/${board_name}_${project_name}.xpr

# Create the project
create_project -part $part_name ${board_name}_${project_name} tmp

# Set the board part
set_property BOARD_PART $board_part [current_project]

# Collect the paths to vendor cores directories
set vendor_cores_paths {}
foreach vendor $core_vendor_list {
  set vendor_cores_path "tmp/cores/$vendor"
  lappend vendor_cores_paths $vendor_cores_path
}
foreach vendor_path $vendor_cores_paths {
  puts "Vendor cores path: $vendor_path"
}
# Add the path to the custom IP core packages
set_property IP_REPO_PATHS $vendor_cores_paths [current_project]
# Load the custom IP source files
update_ip_catalog

################################################################################
### Define a set of Tcl procedures to simplify the creation of block designs
################################################################################

# Procedure for connecting (wiring) two ports together
proc wire {name1 name2} {
  set port1 [get_bd_pins $name1]
  set port2 [get_bd_pins $name2]
  if {[llength $port1] == 1 && [llength $port2] == 1} {
    connect_bd_net $port1 $port2
    return
  }
  set port1 [get_bd_intf_pins $name1]
  set port2 [get_bd_intf_pins $name2]
  if {[llength $port1] == 1 && [llength $port2] == 1} {
    connect_bd_intf_net $port1 $port2
    return
  }
  error "** ERROR: can't connect $name1 and $name2"
}

# Procedure for creating a cell
proc cell {cell_vlnv cell_name {cell_props {}} {cell_ports {}}} {
  set cell [create_bd_cell -type ip -vlnv $cell_vlnv $cell_name]
  set prop_list {}
  foreach {prop_name prop_value} [uplevel 1 [list subst $cell_props]] {
    lappend prop_list CONFIG.$prop_name $prop_value
  }
  if {[llength $prop_list] > 1} {
    set_property -dict $prop_list $cell
  }
  foreach {local_name remote_name} [uplevel 1 [list subst $cell_ports]] {
    wire $cell_name/$local_name $remote_name
  }
}

# Procedure for creating a module sourced from another tcl script
proc module {module_name module_body {module_ports {}}} {
  set instance [current_bd_instance .]
  current_bd_instance [create_bd_cell -type hier $module_name]
  eval $module_body
  current_bd_instance $instance
  foreach {local_name remote_name} [uplevel 1 [list subst $module_ports]] {
    wire $module_name/$local_name $remote_name
  }
}

proc design {design_name design_body} {
  set design [current_bd_design]
  create_bd_design $design_name
  eval $design_body
  validate_bd_design
  save_bd_design
  current_bd_design $design
}

proc container {container_name container_designs {container_ports {}}} {
  set reference [lindex $container_designs 0]
  set container [create_bd_cell -type container -reference $reference $container_name]
  foreach {local_name remote_name} [uplevel 1 [list subst $container_ports]] {
    wire $container_name/$local_name $remote_name
  }
  set list {}
  foreach item $container_designs {
    lappend list $item.bd
  }
  set list [join $list :]
  set_property CONFIG.ENABLE_DFX true $container
  set_property CONFIG.LIST_SYNTH_BD $list $container
  set_property CONFIG.LIST_SIM_BD $list $container
}

proc addr {offset range port master} {
  set object [get_bd_intf_pins $port]
  set segment [get_bd_addr_segs -of_objects $object]
  set config [list Master $master Clk Auto]
  apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config $config $object
  assign_bd_address -offset $offset -range $range $segment
}

##############################################################################
## End of block design helper procedures
##############################################################################

# Start the block design
create_bd_design system

# Execute the port definition and block design scripts for the project, by board
source projects/$project_name/ports.tcl
source projects/$project_name/block_design.tcl

# Clear out the processes defined above to avoid conflicts, now that the block design is complete
rename wire {}
rename cell {}
rename module {}
rename design {}
rename container {}
rename addr {}

set system [get_files system.bd]

set_property SYNTH_CHECKPOINT_MODE None $system

generate_target all $system
make_wrapper -files $system -top

set wrapper [fileutil::findByPattern tmp/${board_name}_${project_name}.gen system_wrapper.v]

add_files -norecurse $wrapper

set_property TOP system_wrapper [current_fileset]

# Load all Verilog and SystemVerilog source files from the project folder, as well as any .mem files
set files [glob -nocomplain projects/$project_name/*.v projects/$project_name/*.sv, projects/$project_name/*.mem]
if {[llength $files] > 0} {
  add_files -norecurse $files
}

# Load all XDC constraint files specific to the board from the project folder
set files [glob -nocomplain projects/$project_name/$board_name/*.xdc]
if {[llength $files] > 0} {
  add_files -norecurse -fileset constrs_1 $files
}

set_property VERILOG_DEFINE {TOOL_VIVADO} [current_fileset]

set_property STRATEGY Flow_PerfOptimized_high [get_runs synth_1]
set_property STRATEGY Performance_ExploreWithRemap [get_runs impl_1]

close_project
