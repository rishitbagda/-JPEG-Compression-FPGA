# Build the project created by create_project.tcl.
set root [file normalize [file join [file dirname [info script]] ..]]
open_project [file join $root build jpeg_fpga jpeg_fpga.xpr]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis did not finish successfully" }
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Implementation did not finish successfully" }
set result [file join $root build jpeg_fpga jpeg_fpga.runs impl_1 jpeg_board_top.bit]
if {![file exists $result]} { error "Expected bitstream was not generated" }
puts "Generated bitstream: $result"
close_project
