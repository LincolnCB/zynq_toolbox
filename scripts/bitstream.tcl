# Create the bitstream file for the project
# Expects that `tmp/$project_name.xpr` exists
# Arguments:
#   0: project_name
#   1: compress

set project_name [lindex $argv 0]
set compress [lindex $argv 1]

open_project tmp/$project_name.xpr

# If the implementation is not complete, run the implementation to completion
if {([get_property CURRENT_STEP [get_runs impl_1]] != "write_bitstream") || ([get_property PROGRESS [get_runs impl_1]] != "100%")} {
  launch_runs impl_1 -to_step write_bitstream
  wait_on_run impl_1
}

# Implementation needs to be opened to write the bitstream
open_run [get_runs impl_1]

# Add the compression before writing the bitstream
if {$compress == "true"} {
  set_property BITSTREAM.GENERAL.COMPRESS TRUE [get_designs impl_1]
}

# Write the bitstream
write_bitstream -force -file tmp/${project_name}_compressed.bit

close_project
