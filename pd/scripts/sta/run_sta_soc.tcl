###############################################################################
# OpenSTA Script — Full SoC Multi-Corner Analysis
# Usage:  sta scripts/sta/run_sta_soc.tcl   (run from pd/ directory)
###############################################################################

set LIB_DIR    $::env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib
set NETLIST    results/synth/soc_top_netlist.v
set SDC        constraints/soc_top.sdc
set RPT_DIR    results/sta

file mkdir $RPT_DIR

# ==============================================================
# Define corners and read libraries
# ==============================================================
define_corners tt ss ff

read_liberty -corner tt ${LIB_DIR}/sky130_fd_sc_hd__tt_025C_1v80.lib
read_liberty -corner ss ${LIB_DIR}/sky130_fd_sc_hd__ss_100C_1v60.lib
read_liberty -corner ff ${LIB_DIR}/sky130_fd_sc_hd__ff_n40C_1v95.lib

read_verilog $NETLIST
link_design soc_top
read_sdc $SDC

# ==============================================================
# TT Corner — Setup + Hold
# ==============================================================
puts "\n============ TT Corner ============"
report_checks -corner tt -path_delay max -sort_by_slack -format full_clock_expanded \
    -fields {slew trans cap input_pins} -digits 3 \
    > ${RPT_DIR}/soc_setup_tt.rpt
report_checks -corner tt -path_delay max -sort_by_slack -group_path_count 10 \
    >> ${RPT_DIR}/soc_setup_tt.rpt
report_checks -corner tt -path_delay min -sort_by_slack -format full_clock_expanded \
    -fields {slew trans cap input_pins} -digits 3 \
    > ${RPT_DIR}/soc_hold_tt.rpt

puts "TT Setup (top 5):"
report_checks -corner tt -path_delay max -sort_by_slack -group_path_count 5

# ==============================================================
# SS Corner — Worst Setup
# ==============================================================
puts "\n============ SS Corner ============"
report_checks -corner ss -path_delay max -sort_by_slack -format full_clock_expanded \
    -fields {slew trans cap input_pins} -digits 3 \
    > ${RPT_DIR}/soc_setup_ss.rpt
report_checks -corner ss -path_delay max -sort_by_slack -group_path_count 10 \
    >> ${RPT_DIR}/soc_setup_ss.rpt
report_checks -corner ss -path_delay min -sort_by_slack -format full_clock_expanded \
    -digits 3 > ${RPT_DIR}/soc_hold_ss.rpt

puts "SS Setup (top 5):"
report_checks -corner ss -path_delay max -sort_by_slack -group_path_count 5

# ==============================================================
# FF Corner — Worst Hold
# ==============================================================
puts "\n============ FF Corner ============"
report_checks -corner ff -path_delay min -sort_by_slack -format full_clock_expanded \
    -fields {slew trans cap input_pins} -digits 3 \
    > ${RPT_DIR}/soc_hold_ff.rpt
report_checks -corner ff -path_delay max -sort_by_slack -format full_clock_expanded \
    -digits 3 > ${RPT_DIR}/soc_setup_ff.rpt

puts "FF Hold (top 5):"
report_checks -corner ff -path_delay min -sort_by_slack -group_path_count 5

# ==============================================================
# Global TNS/WNS summary (across all corners)
# ==============================================================
puts "\n============ Global Summary ============"
report_tns
report_wns

# ==============================================================
# NOTE on pre-CTS timing
# ==============================================================
puts "\n============ Pre-CTS Timing Notes ============"
puts "WARNING: Pre-CTS STA shows massive violations from high-fanout"
puts "reset nets (~1200+ loads with no buffer tree). These will be"
puts "resolved by CTS buffer insertion during PnR (OpenROAD)."
puts "Focus on non-reset datapath paths for actual timing closure."

puts "\n=========================================="
puts " SoC STA Complete — 3 corners analyzed"
puts " Reports in: ${RPT_DIR}/soc_*.rpt"
puts "=========================================="

exit
