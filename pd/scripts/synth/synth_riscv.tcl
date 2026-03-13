###############################################################################
# Yosys Synthesis Script — RISC-V Subsystem (riscv_subsys_top)
# Target: SKY130 HD standard cells
# Usage:  yosys -c scripts/synth/synth_riscv.tcl   (run from pd/ directory)
#
# Includes: Ibex RV32IMC core (sv2v-converted), AXI interconnect,
#           AXI-Lite peripherals, SRAM controllers (blackboxed memories)
###############################################################################

yosys -import

set TOP        riscv_subsys_top
set LIB_DIR    /home/anirudh/.volare/volare/sky130/versions/78b7bc32ddb4b6f14f76883c2e2dc5b5de9d1cbc/sky130A/libs.ref/sky130_fd_sc_hd/lib
set LIB_TT    ${LIB_DIR}/sky130_fd_sc_hd__tt_025C_1v80.lib
set OUT_DIR    results/synth
set RPT_DIR    results/synth

file mkdir $OUT_DIR
file mkdir $RPT_DIR

# --- Read Ibex RISC-V Core (sv2v-converted) ---
read_verilog ibex_v2k/ibex_all.v

# --- Read RISC-V Subsystem RTL ---
read_verilog ../rtl/riscv/riscv_subsys_top.v
read_verilog ../rtl/riscv/axi_interconnect.v
read_verilog ../rtl/riscv/axilite_interconnect.v
read_verilog ../rtl/riscv/riscv_axi_addr_decoder.v
read_verilog ../rtl/riscv/riscv_axi_arbiter.v
read_verilog ../rtl/riscv/riscv_axi_to_axilite_bridge.v
read_verilog ../rtl/riscv/riscv_axilite_addr_decoder.v
read_verilog ../rtl/riscv/ibus_axi_adapter.v
read_verilog ../rtl/riscv/dbus_axi_adapter.v
read_verilog ../rtl/riscv/onchip_sram.v

# Blackbox stubs for large memories
read_verilog synth_stubs/sram_bank_bb.v
read_verilog synth_stubs/boot_rom_bb.v

# Peripherals
read_verilog ../rtl/riscv/uart_peripheral.v
read_verilog ../rtl/riscv/uart_tx.v
read_verilog ../rtl/riscv/uart_rx.v
read_verilog ../rtl/riscv/uart_fifo.v
read_verilog ../rtl/riscv/gpio_peripheral.v
read_verilog ../rtl/riscv/irq_controller.v
read_verilog ../rtl/riscv/timer_clint.v
read_verilog ../rtl/riscv/rst_sync.v

# --- Synthesize ---
synth -top $TOP -flatten

# --- Technology mapping to SKY130 ---
dfflibmap -liberty $LIB_TT
# Map latches to SKY130 cells (Ibex clock gating uses DLATCH_N)
techmap -map +/techmap.v
abc -liberty $LIB_TT -D 10000
# Ensure any remaining latches get mapped
hilomap -hicell sky130_fd_sc_hd__conb_1 HI -locell sky130_fd_sc_hd__conb_1 LO

# --- Clean up ---
opt_clean -purge

# --- Reports ---
tee -o ${RPT_DIR}/riscv_subsys_top_area.rpt stat -liberty $LIB_TT
tee -o ${RPT_DIR}/riscv_subsys_top_check.rpt check

# --- Write outputs ---
write_verilog -noattr -noexpr -nohex ${OUT_DIR}/riscv_subsys_top_netlist.v
write_json ${OUT_DIR}/riscv_subsys_top.json

puts "=========================================="
puts " RISC-V Subsystem Synthesis Complete"
puts " Netlist: ${OUT_DIR}/riscv_subsys_top_netlist.v"
puts " Area:    ${RPT_DIR}/riscv_subsys_top_area.rpt"
puts "=========================================="
