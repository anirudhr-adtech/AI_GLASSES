###############################################################################
# Yosys Synthesis Script — SPI Subsystem (spi_master)
# Target: SKY130 HD standard cells
# Usage:  yosys -c scripts/synth/synth_spi.tcl   (run from pd/ directory)
###############################################################################

yosys -import

set TOP        spi_master
set LIB_DIR    $::env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib
set LIB_TT    ${LIB_DIR}/sky130_fd_sc_hd__tt_025C_1v80.lib
set OUT_DIR    results/synth
set RPT_DIR    results/synth

file mkdir $OUT_DIR
file mkdir $RPT_DIR

# --- Read RTL ---
read_verilog ../rtl/spi/spi_clk_gen.v
read_verilog ../rtl/spi/spi_shift_reg.v
read_verilog ../rtl/spi/spi_master_fsm.v
read_verilog ../rtl/spi/spi_tx_fifo.v
read_verilog ../rtl/spi/spi_rx_fifo.v
read_verilog ../rtl/spi/spi_regfile.v
read_verilog ../rtl/spi/spi_master.v

# --- Use the standard synth command (handles flatten + opt + tech map) ---
synth -top $TOP -flatten

# --- Technology mapping to SKY130 ---
dfflibmap -liberty $LIB_TT
abc -D 10000 -liberty $LIB_TT

# --- Clean up ---
opt_clean -purge

# --- Reports ---
tee -o ${RPT_DIR}/spi_master_area.rpt stat -liberty $LIB_TT
tee -o ${RPT_DIR}/spi_master_check.rpt check

# --- Write outputs ---
write_verilog -noattr -noexpr -nohex ${OUT_DIR}/spi_master_netlist.v
write_json ${OUT_DIR}/spi_master.json

puts "=========================================="
puts " SPI Synthesis Complete"
puts " Netlist: ${OUT_DIR}/spi_master_netlist.v"
puts " Area:    ${RPT_DIR}/spi_master_area.rpt"
puts "=========================================="
