# Export the utilization report for the current project
# Expects that `tmp/$project_dir/project.xpr` exists
# Arguments:
#   0: project_dir
set project_dir [lindex $argv 0]

# Check the project
if {![file exists "tmp/$project_dir/project.xpr"]} {
  puts "Error: Project file tmp/$project_dir/project.xpr does not exist."
  exit 1
}

# Make sure the reports directory exists
if {![file exists "tmp_reports/$project_dir"]} {
  file mkdir "tmp_reports/$project_dir"
}

# Remove any old reports
if {[file exists "tmp_reports/$project_dir/hierarchical_utilization.txt"]} {
  file delete "tmp_reports/$project_dir/hierarchical_utilization.txt"
}

# Open the project
open_project tmp/$project_dir/project.xpr

# Open the synthesis run
open_run [get_runs synth_1]

# Write the heirarchical utilization report
report_utilization -hierarchical -file "tmp_reports/$project_dir/hierarchical_utilization.txt"

close_project
