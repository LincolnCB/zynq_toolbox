# Post-route hook for impl_1 (set as STEPS.ROUTE_DESIGN.TCL.POST by project.tcl).
# The first route pass works from estimated delays and can leave small hold violations on short
# paths it believed were met (no hold detours added). A second pass from the actual routes closes them.
# Does nothing when hold is already met.

set whs [get_property SLACK [get_timing_paths -delay_type min]]
if {$whs ne "" && $whs < 0} {
  puts "INFO: post-route WHS is $whs ns -- re-routing with -directive Explore to fix hold"
  route_design -directive Explore
}
