# Make the hardware definition .xsa file for a given project
# Expects that `tmp/$project_name.xpr` exists
# Arguments:
#   0: project_name
set project_name [lindex $argv 0]

open_project tmp/$project_name.xpr

# If the implementation is not complete, run the implementation to completion
if {([get_property CURRENT_STEP [get_runs impl_1]] != "write_bitstream") || ([get_property PROGRESS [get_runs impl_1]] != "100%")} {
  launch_runs impl_1 -to_step write_bitstream
  wait_on_run impl_1
}

# Write the hardware definition with the (uncompressed) bitstream included
write_hw_platform -fixed -include_bit -force -file tmp/$project_name.xsa

close_project
