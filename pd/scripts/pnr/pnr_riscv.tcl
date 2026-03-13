###############################################################################
# OpenROAD PnR Script — RISC-V Subsystem (riscv_subsys_top)
# Usage:  openroad -exit scripts/pnr/pnr_riscv.tcl
# Run from: pd/ directory
#
# Flow: Read netlist -> Floorplan -> Power grid -> Placement -> CTS -> Route
#
# Key design decisions:
#   - 100 MHz target (10ns) for SKY130
#   - 23,474 cells, ~206K um^2 stdcell area
#   - 4x sram_bank (400x300 each) + 1x boot_rom (100x100)
#   - Die 1600x1200, core 1560x1160 for macro + stdcell placement
#   - Macros placed in top half: 2 SRAM banks per row, boot_rom at corner
###############################################################################

set TOP        riscv_subsys_top
set PDK_ROOT   /home/anirudh/.volare/volare/sky130/versions/78b7bc32ddb4b6f14f76883c2e2dc5b5de9d1cbc
set LIB_DIR    ${PDK_ROOT}/sky130A/libs.ref/sky130_fd_sc_hd/lib
set LEF_DIR    ${PDK_ROOT}/sky130A/libs.ref/sky130_fd_sc_hd/lef
set TECH_LEF   ${PDK_ROOT}/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef
set LIB_TT     ${LIB_DIR}/sky130_fd_sc_hd__tt_025C_1v80.lib
set CELL_LEF   ${LEF_DIR}/sky130_fd_sc_hd.lef
set NETLIST    results/synth/riscv_subsys_top_netlist_noparam.v
set SDC        constraints/riscv_subsys_top_pnr.sdc
set OUT_DIR    results/pnr
set RPT_DIR    results/pnr

file mkdir $OUT_DIR
file mkdir $RPT_DIR

# ==============================================================
# 1. Read design
# ==============================================================
puts "\n===== Step 1: Read Design ====="
read_lef $TECH_LEF
read_lef $CELL_LEF
read_lef lef/sram_macros.lef
read_liberty $LIB_TT
read_liberty lib/sram_bank.lib
read_liberty lib/boot_rom.lib
read_verilog $NETLIST
link_design $TOP
read_sdc $SDC

# ==============================================================
# 2. Floorplan
# ==============================================================
puts "\n===== Step 2: Floorplan ====="
# Stdcell area: ~206K um^2 (23K cells)
# Macro area: 4 * 400*300 = 480K + 100*100 = 10K = 490K um^2
# Die 1600x1200, core 1560x1160 = 1,809,600 um^2
# Stdcell utilization: ~206K / (1,809K - 490K) = ~16% (very comfortable)
initialize_floorplan \
    -die_area "0 0 1600 1200" \
    -core_area "20 20 1580 1180" \
    -site unithd

# Define routing tracks for SKY130 HD
make_tracks li1   -x_offset 0.23 -x_pitch 0.46 -y_offset 0.17 -y_pitch 0.34
make_tracks met1  -x_offset 0.17 -x_pitch 0.34 -y_offset 0.17 -y_pitch 0.34
make_tracks met2  -x_offset 0.23 -x_pitch 0.46 -y_offset 0.23 -y_pitch 0.46
make_tracks met3  -x_offset 0.34 -x_pitch 0.68 -y_offset 0.34 -y_pitch 0.68
make_tracks met4  -x_offset 0.46 -x_pitch 0.92 -y_offset 0.46 -y_pitch 0.92
make_tracks met5  -x_offset 1.70 -x_pitch 3.40 -y_offset 1.70 -y_pitch 3.40

# Place SRAM macros: 2x2 grid in top half of die
# Row 1 (top): sram_bank[0] and sram_bank[1]
# Row 2: sram_bank[2] and sram_bank[3]
# boot_rom: bottom-right corner
#
# onchip_sram instantiates 4x sram_bank. Check instance names.
# The synthesis flattens, so instance names come from the netlist.

# We'll try to place by cell names. If the names don't match,
# OpenROAD will warn but continue.

# Place macros using ODB API (handles escaped names)
# SRAM banks (400x300 each): 2x2 grid in top half
# Boot ROM (100x100): top-right corner
set db [ord::get_db]
set chip [$db getChip]
set block [$chip getBlock]

# Define macro placement locations (x_um, y_um)
# Convert to DB units (1000 units/um for SKY130)
set dbu_per_um [$db getTech]
set dbu [[$db getTech] getDbUnitsPerMicron]

set macro_places [list \
    [list {u_sram.gen_banks\[0\].u_sram_bank} 100 860] \
    [list {u_sram.gen_banks\[1\].u_sram_bank} 560 860] \
    [list {u_sram.gen_banks\[2\].u_sram_bank} 100 520] \
    [list {u_sram.gen_banks\[3\].u_sram_bank} 560 520] \
    [list {u_boot_rom} 1060 860] \
]

foreach entry $macro_places {
    set inst_name [lindex $entry 0]
    set x_um [lindex $entry 1]
    set y_um [lindex $entry 2]
    set x_dbu [expr {int($x_um * $dbu)}]
    set y_dbu [expr {int($y_um * $dbu)}]

    set inst [$block findInst $inst_name]
    if {$inst == "NULL"} {
        puts "WARNING: Could not find instance '$inst_name' — trying with backslash prefix"
        set inst [$block findInst "\\$inst_name"]
    }
    if {$inst != "NULL"} {
        $inst setLocation $x_dbu $y_dbu
        $inst setPlacementStatus FIRM
        puts "Placed macro '$inst_name' at ($x_um, $y_um) um"
    } else {
        puts "ERROR: Could not find macro instance '$inst_name'"
    }
}

# ==============================================================
# 3. Power Distribution Network (PDN)
# ==============================================================
puts "\n===== Step 3: PDN ====="
add_global_connection -net VDD -pin_pattern "^VPWR$" -power
add_global_connection -net VDD -pin_pattern "^VPB$"  -power
add_global_connection -net VSS -pin_pattern "^VGND$" -ground
add_global_connection -net VSS -pin_pattern "^VNB$"  -ground

global_connect

set_voltage_domain -name CORE -power VDD -ground VSS

define_pdn_grid -name core_grid -voltage_domains CORE

# Stdcell rails (met1)
add_pdn_stripe -grid core_grid -layer met1 -width 0.48 -followpins

# Vertical stripes (met4)
add_pdn_stripe -grid core_grid -layer met4 -width 1.6 -pitch 50.0 -offset 13.0

# Horizontal stripes (met5)
add_pdn_stripe -grid core_grid -layer met5 -width 1.6 -pitch 50.0 -offset 13.0

# Connections between layers
add_pdn_connect -grid core_grid -layers {met1 met4}
add_pdn_connect -grid core_grid -layers {met4 met5}

pdngen

# ==============================================================
# 4. Placement
# ==============================================================
puts "\n===== Step 4: Placement ====="
# IO pin placement
place_pins -hor_layers met3 -ver_layers met2

# Global placement
global_placement -density 0.5 -pad_left 2 -pad_right 2

# Detailed placement with legalization
detailed_placement
optimize_mirroring

# Check placement
check_placement -verbose

# Report placement
report_design_area > ${RPT_DIR}/riscv_placement_area.rpt
puts "\n--- Placement Summary ---"
report_design_area

# ==============================================================
# 5. Clock Tree Synthesis
# ==============================================================
puts "\n===== Step 5: CTS ====="
# Wire RC from tech LEF layers
set_wire_rc -clock  -layer met3
set_wire_rc -signal -layer met2

# Estimate parasitics before CTS for better timing
estimate_parasitics -placement

# Run CTS
clock_tree_synthesis \
    -buf_list "sky130_fd_sc_hd__clkbuf_4 sky130_fd_sc_hd__clkbuf_8 sky130_fd_sc_hd__clkbuf_16" \
    -root_buf sky130_fd_sc_hd__clkbuf_16 \
    -sink_clustering_enable \
    -sink_clustering_size 30 \
    -sink_clustering_max_diameter 100

# Set propagated clocks for post-CTS analysis
set_propagated_clock [all_clocks]

# Repair clock nets
repair_clock_nets

# CTS report
report_clock_skew > ${RPT_DIR}/riscv_cts_skew.rpt
puts "\n--- Clock Skew Report ---"
report_clock_skew

# ==============================================================
# 6. Post-CTS Optimization
# ==============================================================
puts "\n===== Step 6: Post-CTS Optimization ====="
estimate_parasitics -placement

# Set dont_touch on SRAM/ROM macros AFTER CTS to prevent buffer explosion
# Use ODB to iterate macro instances
set db [ord::get_db]
set chip [$db getChip]
set blk [$chip getBlock]
foreach inst [$blk getInsts] {
    set mname [[$inst getMaster] getName]
    if {$mname == "sram_bank" || $mname == "boot_rom"} {
        set iname [$inst getName]
        if {[catch {set_dont_touch [get_cells $iname]} err]} {
            puts "INFO: Could not set dont_touch on $iname via STA: $err"
        } else {
            puts "Set dont_touch on macro: $iname"
        }
    }
}

# Repair design — catch errors from dont_touch macro net conflicts
if {[catch {repair_design -max_wire_length 600} err]} {
    puts "WARNING: repair_design error: $err"
    puts "Continuing — some long wires may remain unbuffered"
}

# Repair timing
if {[catch {repair_timing -setup} err]} {
    puts "WARNING: repair_timing -setup error: $err"
    puts "Continuing — setup violations may remain"
}

# Hold repair — catch errors from OpenROAD buffer insertion bugs
if {[catch {repair_timing -hold -hold_margin 0.3} err]} {
    puts "WARNING: Hold repair encountered error: $err"
    puts "Continuing without full hold repair — will need post-route ECO"
}

# Re-legalize after buffer insertion
detailed_placement

puts "\n--- Post-CTS Timing ---"
report_checks -path_delay max -sort_by_slack -group_count 3
report_tns
report_wns

# ==============================================================
# 7. Routing
# ==============================================================
puts "\n===== Step 7: Routing ====="
set_routing_layers -signal met1-met5 -clock met1-met5

# Mark power/ground nets as special for router
set db [ord::get_db]
set block [$db getChip]
set block [$block getBlock]
foreach net [$block getNets] {
    set sigtype [$net getSigType]
    if {$sigtype == "POWER" || $sigtype == "GROUND"} {
        $net setSpecial
    }
}

# Global routing
global_route -guide_file ${OUT_DIR}/riscv_route.guide \
    -congestion_iterations 50 \
    -allow_congestion

# Detailed routing
detailed_route \
    -output_drc ${RPT_DIR}/riscv_route_drc.rpt

# ==============================================================
# 8. Post-Route Analysis
# ==============================================================
puts "\n===== Step 8: Post-Route Analysis ====="
estimate_parasitics -global_routing

# Final timing reports
report_checks -path_delay max -sort_by_slack -group_count 10 \
    > ${RPT_DIR}/riscv_postroute_setup.rpt
report_checks -path_delay min -sort_by_slack -group_count 10 \
    > ${RPT_DIR}/riscv_postroute_hold.rpt
report_tns > ${RPT_DIR}/riscv_postroute_tns.rpt
report_wns > ${RPT_DIR}/riscv_postroute_wns.rpt

# Design area
report_design_area > ${RPT_DIR}/riscv_postroute_area.rpt

# Print summary
puts "\n========== Post-Route Timing Summary =========="
report_checks -path_delay max -sort_by_slack -group_count 5
report_tns
report_wns
puts ""
report_design_area

# ==============================================================
# 9. Write outputs
# ==============================================================
write_def ${OUT_DIR}/riscv_subsys_top_routed.def
write_verilog ${OUT_DIR}/riscv_subsys_top_pnr.v

puts "\n=========================================="
puts " RISC-V Subsystem PnR Complete"
puts " DEF:     ${OUT_DIR}/riscv_subsys_top_routed.def"
puts " Netlist: ${OUT_DIR}/riscv_subsys_top_pnr.v"
puts " Reports: ${RPT_DIR}/riscv_*.rpt"
puts "=========================================="

exit
