###############################################################################
# Yosys Synthesis Script — AXI Crossbar Subsystem (axi_crossbar)
# Target: SKY130 HD standard cells
# Usage:  yosys -c scripts/synth/synth_axi.tcl   (run from pd/ directory)
###############################################################################

yosys -import

set TOP        axi_crossbar
set LIB_DIR    /home/anirudh/.volare/volare/sky130/versions/78b7bc32ddb4b6f14f76883c2e2dc5b5de9d1cbc/sky130A/libs.ref/sky130_fd_sc_hd/lib
set LIB_TT    ${LIB_DIR}/sky130_fd_sc_hd__tt_025C_1v80.lib
set OUT_DIR    results/synth
set RPT_DIR    results/synth

file mkdir $OUT_DIR
file mkdir $RPT_DIR

# --- Read RTL ---
read_verilog ../rtl/axi/axi_arbiter.v
read_verilog ../rtl/axi/axi_addr_decoder.v
read_verilog ../rtl/axi/axi_slave_port.v
read_verilog ../rtl/axi/axi_master_if.v
read_verilog ../rtl/axi/axi_2to1_mux.v
read_verilog ../rtl/axi/axi_rd_mux.v
read_verilog ../rtl/axi/axi_wr_mux.v
read_verilog ../rtl/axi/axi_resp_demux.v
read_verilog ../rtl/axi/axi_width_converter.v
read_verilog ../rtl/axi/axi_upsizer.v
read_verilog ../rtl/axi/axi_downsizer.v
read_verilog ../rtl/axi/axi_to_axilite_bridge.v
read_verilog ../rtl/axi/axi_timeout.v
read_verilog ../rtl/axi/axi_error_slave.v
read_verilog ../rtl/axi/axilite_fabric.v
read_verilog ../rtl/axi/axilite_addr_decoder.v
read_verilog ../rtl/axi/axilite_mux.v
read_verilog ../rtl/axi/axi_crossbar.v

# --- Synthesize ---
synth -top $TOP -flatten

# --- Technology mapping to SKY130 ---
dfflibmap -liberty $LIB_TT
abc -liberty $LIB_TT -D 10000

# --- Clean up ---
opt_clean -purge

# --- Reports ---
tee -o ${RPT_DIR}/axi_crossbar_area.rpt stat -liberty $LIB_TT
tee -o ${RPT_DIR}/axi_crossbar_check.rpt check

# --- Write outputs ---
write_verilog -noattr -noexpr -nohex ${OUT_DIR}/axi_crossbar_netlist.v
write_json ${OUT_DIR}/axi_crossbar.json

puts "=========================================="
puts " AXI Crossbar Synthesis Complete"
puts " Netlist: ${OUT_DIR}/axi_crossbar_netlist.v"
puts " Area:    ${RPT_DIR}/axi_crossbar_area.rpt"
puts "=========================================="
