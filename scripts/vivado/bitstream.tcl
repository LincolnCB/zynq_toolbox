# Create the bitstream file for the project
# Arguments:
#   0: project_dir
#   1: compress

set project_dir [lindex $argv 0]
set compress [lindex $argv 1]

# Check the project
if {![file exists "tmp/$project_dir/project.xpr"]} {
  puts "Error: Project file tmp/$project_dir/project.xpr does not exist."
  exit 1
}

# Open the project
open_project tmp/$project_dir/project.xpr

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
  # Write the bitstream
  write_bitstream -force -file tmp/${project_dir}/compressed_bitstream.bit
} else {
  # Write the bitstream
  write_bitstream -force -file tmp/${project_dir}/bitstream.bit
}


close_project
