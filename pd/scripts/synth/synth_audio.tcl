###############################################################################
# Yosys Synthesis Script — Audio Subsystem (audio_subsys_top)
# Target: SKY130 HD standard cells
# Usage:  yosys -c scripts/synth/synth_audio.tcl   (run from pd/ directory)
###############################################################################

yosys -import

set TOP        audio_subsys_top
set LIB_DIR    $::env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib
set LIB_TT    ${LIB_DIR}/sky130_fd_sc_hd__tt_025C_1v80.lib
set OUT_DIR    results/synth
set RPT_DIR    results/synth

file mkdir $OUT_DIR
file mkdir $RPT_DIR

# --- Read RTL (21 modules, all self-contained, no blackboxes needed) ---
# I2S interface
read_verilog ../rtl/audio/i2s_rx.v
read_verilog ../rtl/audio/i2s_sync.v

# Audio capture and windowing
read_verilog ../rtl/audio/audio_fifo.v
read_verilog ../rtl/audio/hamming_rom.v
read_verilog ../rtl/audio/audio_window.v

# FFT engine
read_verilog ../rtl/audio/fft_twiddle_rom.v
read_verilog ../rtl/audio/fft_addr_gen.v
read_verilog ../rtl/audio/fft_butterfly.v
read_verilog ../rtl/audio/fft_engine.v

# Spectral processing
read_verilog ../rtl/audio/power_spectrum.v
read_verilog ../rtl/audio/mel_coeff_rom.v
read_verilog ../rtl/audio/mel_filterbank.v
read_verilog ../rtl/audio/log_lut_rom.v
read_verilog ../rtl/audio/log_compress.v

# DCT / MFCC output
read_verilog ../rtl/audio/dct_coeff_rom.v
read_verilog ../rtl/audio/dct_unit.v
read_verilog ../rtl/audio/mfcc_out_buf.v

# DMA, register file, controller, top
read_verilog ../rtl/audio/audio_dma.v
read_verilog ../rtl/audio/audio_regfile.v
read_verilog ../rtl/audio/audio_controller.v
read_verilog ../rtl/audio/audio_subsys_top.v

# --- Use the standard synth command (handles flatten + opt + tech map) ---
synth -top $TOP -flatten

# --- Technology mapping to SKY130 (100 MHz → 10 ns → 10000 ps) ---
dfflibmap -liberty $LIB_TT
abc -liberty $LIB_TT -D 10000

# --- Clean up ---
opt_clean -purge

# --- Reports ---
tee -o ${RPT_DIR}/audio_subsys_top_area.rpt stat -liberty $LIB_TT
tee -o ${RPT_DIR}/audio_subsys_top_check.rpt check

# --- Write outputs ---
write_verilog -noattr -noexpr -nohex ${OUT_DIR}/audio_subsys_top_netlist.v
write_json ${OUT_DIR}/audio_subsys_top.json

puts "=========================================="
puts " Audio Subsystem Synthesis Complete"
puts " Netlist: ${OUT_DIR}/audio_subsys_top_netlist.v"
puts " Area:    ${RPT_DIR}/audio_subsys_top_area.rpt"
puts "=========================================="
