###############################################################################
# Magic DRC Script — NPU Subsystem
# Usage:  magic -dnull -noconsole -T $PDK_ROOT/sky130A/libs.tech/magic/sky130A.tech
#             < scripts/pv/drc_npu.tcl
# Run from: pd/ directory
###############################################################################

# Read standard cell GDS first (provides cell layouts)
gds read $::env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds

# Read routed layout (DEF)
def read results/pnr/npu_top_routed.def

# Select the top cell
load npu_top

# Run DRC
select top cell
drc check
drc catchup

# Write DRC report
set drc_count [drc count total]
puts "============================================"
puts " DRC Results: $drc_count violations"
puts "============================================"

drc listall why > results/pv/npu_drc_report.txt

# Write GDS for LVS
gds write results/pv/npu_top.gds

puts "DRC report: results/pv/npu_drc_report.txt"
puts "GDS output: results/pv/npu_top.gds"

quit -noprompt
