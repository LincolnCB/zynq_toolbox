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

# Load in the other source files (modules)
set files [glob -nocomplain modules/*.v]
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
# Set the vendor display name and company URL based on the vendor name
if {$vendor_name eq "pavel-demin"} {
  set_property VENDOR_DISPLAY_NAME {Pavel Demin} $core
  set_property COMPANY_URL {https://github.com/pavel-demin/red-pitaya-notes} $core
} elseif {$vendor_name eq "open-mri"} {
  set_property VENDOR_DISPLAY_NAME {Open MRI} $core
  set_property COMPANY_URL {https://github.com/OpenMRI/ocra} $core
} elseif {$vendor_name eq "lcb"} {
  set_property VENDOR_DISPLAY_NAME {Lincoln Craven-Brightman} $core
  set_property COMPANY_URL {https://github.com/LincolnCB/rev_d_shim} $core
}
set_property SUPPORTED_FAMILIES {zynq Production} $core

puts "Packaging core: $vendor_name:user:$core_name:1.0"

# Package the core
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core

# Exit the core project
close_project
