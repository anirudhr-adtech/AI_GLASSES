###############################################################################
# Yosys Synthesis Script — I2C Subsystem (i2c_master)
# Target: SKY130 HD standard cells
# Usage:  yosys -c scripts/synth/synth_i2c.tcl   (run from pd/ directory)
###############################################################################

yosys -import

set TOP        i2c_master
set LIB_DIR    $::env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib
set LIB_TT    ${LIB_DIR}/sky130_fd_sc_hd__tt_025C_1v80.lib
set OUT_DIR    results/synth
set RPT_DIR    results/synth

file mkdir $OUT_DIR
file mkdir $RPT_DIR

# --- Read RTL ---
read_verilog ../rtl/i2c/i2c_scl_gen.v
read_verilog ../rtl/i2c/i2c_shift_reg.v
read_verilog ../rtl/i2c/i2c_master_fsm.v
read_verilog ../rtl/i2c/i2c_tx_fifo.v
read_verilog ../rtl/i2c/i2c_rx_fifo.v
read_verilog ../rtl/i2c/i2c_regfile.v
read_verilog ../rtl/i2c/i2c_master.v

# --- Use the standard synth command (handles flatten + opt + tech map) ---
synth -top $TOP -flatten

# --- Technology mapping to SKY130 ---
dfflibmap -liberty $LIB_TT
abc -D 10000 -liberty $LIB_TT

# --- Clean up ---
opt_clean -purge

# --- Reports ---
tee -o ${RPT_DIR}/i2c_master_area.rpt stat -liberty $LIB_TT
tee -o ${RPT_DIR}/i2c_master_check.rpt check

# --- Write outputs ---
write_verilog -noattr -noexpr -nohex ${OUT_DIR}/i2c_master_netlist.v
write_json ${OUT_DIR}/i2c_master.json

puts "=========================================="
puts " I2C Synthesis Complete"
puts " Netlist: ${OUT_DIR}/i2c_master_netlist.v"
puts " Area:    ${RPT_DIR}/i2c_master_area.rpt"
puts "=========================================="
