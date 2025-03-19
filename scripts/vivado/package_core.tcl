# This script creates a custom Vivado IP core for a given core path and part name.
# The cores are packaged to tmp/cores/[vendor_name]/[core_name] and used in the project.tcl script.

package require fileutil
package require json

# First argument is the path to the core (relative to the top-level cores/ directory)
set core_path [lindex $argv 0]
# Second argument is the part name
set part_name [lindex $argv 1]

# Split the core path into "vendor_name" and "core_name" for use in the commands below
set vendor_name [file dirname $core_path]
set core_name [file tail $core_path]

# Clear out old build files
file delete -force tmp/cores/$core_path tmp/cores/$core_path.cache tmp/cores/$core_path.hw tmp/cores/$core_path.ip_user_files tmp/cores/$core_path.sim tmp/cores/$core_path.xpr

# Create the core project
create_project -part $part_name $core_name tmp/cores/$vendor_name

# Add the main source file to the core project
add_files -norecurse cores/$core_path.v

# Set the main (core_name) module as the top module
set_property TOP $core_name [current_fileset]

# Load in the other source files (submodules from the vendor directory)
set files [glob -nocomplain cores/$vendor_name/submodules/*.v]
if {[llength $files] > 0} {
  add_files -norecurse $files
}

# Set the IP packaging path
ipx::package_project -root_dir tmp/cores/$core_path -import_files cores/$core_path.v

# Get the Vivado core
set core [ipx::current_core]

# Set the core properties
set_property VERSION {1.0} $core
set_property NAME $core_name $core
set_property LIBRARY {user} $core
set_property VENDOR $vendor_name $core

## Extract the info for the vendor display name and company URL
# Read the json config for the board into a dict
set vendor_info_fname cores/$vendor_name/info/vendor_info.json
if {[file exists $vendor_info_fname]} {
    set vendor_info_fd [open $vendor_info_fname "r"]
} else {
    error "Vendor info file ${vendor_info_fname} missing."
}
set vendor_info_str [read $vendor_info_fd]
close $vendor_info_fd
set vendor_info_dict [json::json2dict $vendor_info_str]

set_property VENDOR_DISPLAY_NAME [dict get $vendor_info_dict display_name] $core
set_property COMPANY_URL [dict get $vendor_info_dict url] $core
set_property SUPPORTED_FAMILIES {zynq Production} $core

puts "Packaging core: $vendor_name:user:$core_name:1.0"

# Package the core
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core

# Exit the core project
close_project
