###############################################################################
# Yosys Synthesis Script — DDR Subsystem (ddr_wrapper)
# Target: SKY130 HD standard cells
# Usage:  yosys -c scripts/synth/synth_ddr.tcl   (run from pd/ directory)
# Note:   Only synthesizable RTL is included. Simulation model files
#         (axi_mem_model, axi_mem_*_channel, mem_array, mem_preloader)
#         are excluded.
###############################################################################

yosys -import

set TOP        ddr_wrapper
set LIB_DIR    /home/anirudh/.volare/volare/sky130/versions/78b7bc32ddb4b6f14f76883c2e2dc5b5de9d1cbc/sky130A/libs.ref/sky130_fd_sc_hd/lib
set LIB_TT    ${LIB_DIR}/sky130_fd_sc_hd__tt_025C_1v80.lib
set OUT_DIR    results/synth
set RPT_DIR    results/synth

file mkdir $OUT_DIR
file mkdir $RPT_DIR

# --- Read RTL (synthesis files only, no sim model) ---
read_verilog ../rtl/ddr/latency_pipe.v
read_verilog ../rtl/ddr/backpressure_gen.v
read_verilog ../rtl/ddr/qos_mapper.v
read_verilog ../rtl/ddr/burst_splitter.v
read_verilog ../rtl/ddr/axi_width_128to64.v
read_verilog ../rtl/ddr/axi4_to_axi3_bridge.v
read_verilog ../rtl/ddr/ddr_wrapper.v

# --- Use the standard synth command (handles flatten + opt + tech map) ---
synth -top $TOP -flatten

# --- Technology mapping to SKY130 ---
dfflibmap -liberty $LIB_TT
abc -D 10000 -liberty $LIB_TT

# --- Clean up ---
opt_clean -purge

# --- Reports ---
tee -o ${RPT_DIR}/ddr_wrapper_area.rpt stat -liberty $LIB_TT
tee -o ${RPT_DIR}/ddr_wrapper_check.rpt check

# --- Write outputs ---
write_verilog -noattr -noexpr -nohex ${OUT_DIR}/ddr_wrapper_netlist.v
write_json ${OUT_DIR}/ddr_wrapper.json

puts "=========================================="
puts " DDR Synthesis Complete"
puts " Netlist: ${OUT_DIR}/ddr_wrapper_netlist.v"
puts " Area:    ${RPT_DIR}/ddr_wrapper_area.rpt"
puts "=========================================="
