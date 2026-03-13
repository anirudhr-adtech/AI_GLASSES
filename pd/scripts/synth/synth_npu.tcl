###############################################################################
# Yosys Synthesis Script — NPU Subsystem (npu_top)
# Target: SKY130 HD standard cells
# Usage:  yosys -c scripts/synth/synth_npu.tcl   (run from pd/ directory)
###############################################################################

yosys -import

set TOP        npu_top
set LIB_DIR    $::env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib
set LIB_TT    ${LIB_DIR}/sky130_fd_sc_hd__tt_025C_1v80.lib
set OUT_DIR    results/synth
set RPT_DIR    results/synth

file mkdir $OUT_DIR
file mkdir $RPT_DIR

# --- Read RTL ---
read_verilog ../rtl/npu/mac_unit.v
read_verilog ../rtl/npu/npu_mac_array.v
# SRAM buffers: blackbox stubs (real SRAM macros substituted in PnR)
read_verilog synth_stubs/npu_weight_buf_bb.v
read_verilog synth_stubs/npu_act_buf_bb.v
read_verilog ../rtl/npu/npu_quantize.v
read_verilog ../rtl/npu/npu_activation.v
read_verilog ../rtl/npu/dma_weight_ch.v
read_verilog ../rtl/npu/dma_act_ch.v
read_verilog ../rtl/npu/npu_dma.v
read_verilog ../rtl/npu/npu_regfile.v
read_verilog ../rtl/npu/npu_controller.v
read_verilog ../rtl/npu/npu_top.v

# --- Use the standard synth command (handles flatten + opt + tech map) ---
synth -top $TOP -flatten

# --- Technology mapping to SKY130 ---
dfflibmap -liberty $LIB_TT
abc -liberty $LIB_TT -D 5000

# --- Clean up ---
opt_clean -purge

# --- Reports ---
tee -o ${RPT_DIR}/npu_top_area.rpt stat -liberty $LIB_TT
tee -o ${RPT_DIR}/npu_top_check.rpt check

# --- Write outputs ---
write_verilog -noattr -noexpr -nohex ${OUT_DIR}/npu_top_netlist.v
write_json ${OUT_DIR}/npu_top.json

puts "=========================================="
puts " NPU Synthesis Complete"
puts " Netlist: ${OUT_DIR}/npu_top_netlist.v"
puts " Area:    ${RPT_DIR}/npu_top_area.rpt"
puts "=========================================="
