# Portable Vivado project creation. Run from any working directory.
set root [file normalize [file join [file dirname [info script]] ..]]
set width 240
set height 240
if {$argc != 0 && $argc != 2} { error "Pass either no arguments or WIDTH HEIGHT" }
if {$argc == 2} {
    set width [lindex $argv 0]
    set height [lindex $argv 1]
}
foreach dimension [list $width $height] {
    if {![string is integer -strict $dimension] || $dimension <= 0 || $dimension % 8 != 0} {
        error "Frame dimensions must be positive multiples of 8"
    }
}
set project_dir [file join $root build jpeg_fpga]
create_project jpeg_fpga $project_dir -part xc7a100tcsg324-1 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files -norecurse [glob [file join $root rtl *.sv]]
set_property file_type SystemVerilog [get_files *.sv]
add_files -fileset constrs_1 -norecurse [file join $root constraints nexys4ddr_jpeg.xdc]
# Select one end-to-end testbench. Other benches stay available in sim/.
add_files -fileset sim_1 -norecurse [file join $root sim tb_jpeg_jfif_top_240x240_custom.sv]
set_property generic "IMG_W=$width IMG_H=$height" [get_filesets sources_1]
set_property generic "W=$width H=$height" [get_filesets sim_1]
set_property top jpeg_board_top [get_filesets sources_1]
set_property top tb_jpeg_jfif_top [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Project created at $project_dir"
close_project
