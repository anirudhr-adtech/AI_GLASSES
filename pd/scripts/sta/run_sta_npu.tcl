###############################################################################
# OpenSTA Script — NPU Subsystem Multi-Corner Analysis
# Usage:  sta scripts/sta/run_sta_npu.tcl   (run from pd/ directory)
###############################################################################

set LIB_DIR    $::env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib
set NETLIST    results/synth/npu_top_netlist.v
set SDC        constraints/npu_top.sdc
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
link_design npu_top
read_sdc $SDC

# ==============================================================
# TT Corner — Setup + Hold
# ==============================================================
puts "\n============ TT Corner ============"
report_checks -corner tt -path_delay max -sort_by_slack -format full_clock_expanded \
    -fields {slew trans cap input_pins} -digits 3 \
    > ${RPT_DIR}/npu_setup_tt.rpt
report_checks -corner tt -path_delay max -sort_by_slack -group_path_count 10 \
    >> ${RPT_DIR}/npu_setup_tt.rpt
report_checks -corner tt -path_delay min -sort_by_slack -format full_clock_expanded \
    -fields {slew trans cap input_pins} -digits 3 \
    > ${RPT_DIR}/npu_hold_tt.rpt

puts "TT Setup (top 5):"
report_checks -corner tt -path_delay max -sort_by_slack -group_path_count 5

# ==============================================================
# SS Corner — Worst Setup
# ==============================================================
puts "\n============ SS Corner ============"
report_checks -corner ss -path_delay max -sort_by_slack -format full_clock_expanded \
    -fields {slew trans cap input_pins} -digits 3 \
    > ${RPT_DIR}/npu_setup_ss.rpt
report_checks -corner ss -path_delay max -sort_by_slack -group_path_count 10 \
    >> ${RPT_DIR}/npu_setup_ss.rpt
report_checks -corner ss -path_delay min -sort_by_slack -format full_clock_expanded \
    -digits 3 > ${RPT_DIR}/npu_hold_ss.rpt

puts "SS Setup (top 5):"
report_checks -corner ss -path_delay max -sort_by_slack -group_path_count 5

# ==============================================================
# FF Corner — Worst Hold
# ==============================================================
puts "\n============ FF Corner ============"
report_checks -corner ff -path_delay min -sort_by_slack -format full_clock_expanded \
    -fields {slew trans cap input_pins} -digits 3 \
    > ${RPT_DIR}/npu_hold_ff.rpt
report_checks -corner ff -path_delay max -sort_by_slack -format full_clock_expanded \
    -digits 3 > ${RPT_DIR}/npu_setup_ff.rpt

puts "FF Hold (top 5):"
report_checks -corner ff -path_delay min -sort_by_slack -group_path_count 5

# ==============================================================
# Global TNS/WNS summary (across all corners)
# ==============================================================
puts "\n============ Global Summary ============"
report_tns
report_wns

puts "\n=========================================="
puts " NPU STA Complete — 3 corners analyzed"
puts " Reports in: ${RPT_DIR}/npu_*.rpt"
puts "=========================================="

exit
