###############################################################################
# Yosys Synthesis Script — Full SoC (soc_top)
# Target: SKY130 HD standard cells
# Usage:  yosys -c scripts/synth/synth_soc.tcl   (run from pd/ directory)
#
# Strategy:
#   1. Read sv2v-converted Ibex (ibex_v2k/ibex_all.v)
#   2. Read all Verilog subsystem files (blackbox large SRAMs)
#   3. Synthesize with synth -flatten for proper tech mapping
#   4. ABC with 10ns target (100 MHz sys_clk — primary domain)
###############################################################################

yosys -import

set TOP        soc_top
set LIB_DIR    $::env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib
set LIB_TT    ${LIB_DIR}/sky130_fd_sc_hd__tt_025C_1v80.lib
set OUT_DIR    results/synth
set RPT_DIR    results/synth

file mkdir $OUT_DIR
file mkdir $RPT_DIR

# ==============================================================
# 1. Read Ibex RISC-V Core (sv2v-converted Verilog-2005)
# ==============================================================
# Pre-converted from SystemVerilog using:
#   sv2v -DSYNTHESIS -I <include_paths> <all_ibex_sv_files> -w ibex_v2k/ibex_all.v
read_verilog ibex_v2k/ibex_all.v

# ==============================================================
# 2. Read RISC-V Subsystem (Verilog)
# ==============================================================
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
read_verilog ../rtl/riscv/uart_peripheral.v
read_verilog ../rtl/riscv/uart_tx.v
read_verilog ../rtl/riscv/uart_rx.v
read_verilog ../rtl/riscv/uart_fifo.v
read_verilog ../rtl/riscv/gpio_peripheral.v
read_verilog ../rtl/riscv/irq_controller.v
read_verilog ../rtl/riscv/timer_clint.v
read_verilog ../rtl/riscv/rst_sync.v

# ==============================================================
# 3. Read NPU Subsystem (blackbox SRAM buffers)
# ==============================================================
read_verilog ../rtl/npu/mac_unit.v
read_verilog ../rtl/npu/npu_mac_array.v
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

# ==============================================================
# 4. Read AXI Interconnect
# ==============================================================
read_verilog ../rtl/axi/axi_crossbar.v
read_verilog ../rtl/axi/axi_arbiter.v
read_verilog ../rtl/axi/axi_addr_decoder.v
read_verilog ../rtl/axi/axi_slave_port.v
read_verilog ../rtl/axi/axi_master_if.v
read_verilog ../rtl/axi/axi_rd_mux.v
read_verilog ../rtl/axi/axi_wr_mux.v
read_verilog ../rtl/axi/axi_resp_demux.v
read_verilog ../rtl/axi/axi_error_slave.v
read_verilog ../rtl/axi/axi_timeout.v
read_verilog ../rtl/axi/axi_to_axilite_bridge.v
read_verilog ../rtl/axi/axi_upsizer.v
read_verilog ../rtl/axi/axi_downsizer.v
read_verilog ../rtl/axi/axi_width_converter.v
read_verilog ../rtl/axi/axi_2to1_mux.v
read_verilog ../rtl/axi/axilite_fabric.v
read_verilog ../rtl/axi/axilite_addr_decoder.v
read_verilog ../rtl/axi/axilite_mux.v

# ==============================================================
# 5. Read Audio/MFCC Subsystem
# ==============================================================
read_verilog ../rtl/audio/audio_subsys_top.v
read_verilog ../rtl/audio/audio_controller.v
read_verilog ../rtl/audio/audio_regfile.v
read_verilog ../rtl/audio/audio_dma.v
read_verilog ../rtl/audio/audio_fifo.v
read_verilog ../rtl/audio/i2s_rx.v
read_verilog ../rtl/audio/i2s_sync.v
read_verilog ../rtl/audio/audio_window.v
read_verilog ../rtl/audio/hamming_rom.v
read_verilog ../rtl/audio/fft_engine.v
read_verilog ../rtl/audio/fft_butterfly.v
read_verilog ../rtl/audio/fft_addr_gen.v
read_verilog ../rtl/audio/fft_twiddle_rom.v
read_verilog ../rtl/audio/power_spectrum.v
read_verilog ../rtl/audio/mel_filterbank.v
read_verilog ../rtl/audio/mel_coeff_rom.v
read_verilog ../rtl/audio/log_compress.v
read_verilog ../rtl/audio/log_lut_rom.v
read_verilog ../rtl/audio/dct_unit.v
read_verilog ../rtl/audio/dct_coeff_rom.v
read_verilog ../rtl/audio/mfcc_out_buf.v

# ==============================================================
# 6. Read Camera/Vision Subsystem
# ==============================================================
read_verilog ../rtl/camera/cam_subsys_top.v
read_verilog ../rtl/camera/cam_controller.v
read_verilog ../rtl/camera/cam_regfile.v
read_verilog ../rtl/camera/dvp_capture.v
read_verilog ../rtl/camera/dvp_sync.v
read_verilog ../rtl/camera/pixel_fifo.v
read_verilog ../rtl/camera/gray_counter.v
read_verilog ../rtl/camera/pixel_packer.v
read_verilog ../rtl/camera/isp_lite.v
read_verilog ../rtl/camera/line_buffer.v
read_verilog ../rtl/camera/resize_engine.v
read_verilog ../rtl/camera/crop_resize.v
read_verilog ../rtl/camera/crop_engine.v
read_verilog ../rtl/camera/crop_dma_reader.v
read_verilog ../rtl/camera/crop_dma_writer.v
read_verilog ../rtl/camera/frame_buf_ctrl.v
read_verilog ../rtl/camera/video_dma.v
read_verilog ../rtl/camera/yuv2rgb.v

# ==============================================================
# 7. Read DDR Bridge (synthesis-ready only)
# ==============================================================
read_verilog ../rtl/ddr/ddr_wrapper.v
read_verilog ../rtl/ddr/axi4_to_axi3_bridge.v
read_verilog ../rtl/ddr/axi_width_128to64.v
read_verilog ../rtl/ddr/burst_splitter.v
read_verilog ../rtl/ddr/qos_mapper.v

# ==============================================================
# 8. Read Peripheral Subsystems
# ==============================================================
# I2C
read_verilog ../rtl/i2c/i2c_master.v
read_verilog ../rtl/i2c/i2c_master_fsm.v
read_verilog ../rtl/i2c/i2c_regfile.v
read_verilog ../rtl/i2c/i2c_tx_fifo.v
read_verilog ../rtl/i2c/i2c_rx_fifo.v
read_verilog ../rtl/i2c/i2c_scl_gen.v
read_verilog ../rtl/i2c/i2c_shift_reg.v

# SPI
read_verilog ../rtl/spi/spi_master.v
read_verilog ../rtl/spi/spi_master_fsm.v
read_verilog ../rtl/spi/spi_regfile.v
read_verilog ../rtl/spi/spi_tx_fifo.v
read_verilog ../rtl/spi/spi_rx_fifo.v
read_verilog ../rtl/spi/spi_clk_gen.v
read_verilog ../rtl/spi/spi_shift_reg.v

# ==============================================================
# 9. Read SoC Top
# ==============================================================
read_verilog ../rtl/soc/clk_rst_mgr.v
read_verilog ../rtl/soc/soc_top.v

# ==============================================================
# Synthesis — use synth -flatten for proper tech mapping
# ==============================================================
synth -top $TOP -flatten

# Technology mapping to SKY130
dfflibmap -liberty $LIB_TT

# ABC with 10ns target (100 MHz sys_clk)
abc -liberty $LIB_TT -D 10000

opt_clean -purge

# ==============================================================
# Reports
# ==============================================================
tee -o ${RPT_DIR}/soc_top_area.rpt stat -liberty $LIB_TT
tee -o ${RPT_DIR}/soc_top_check.rpt check

# ==============================================================
# Write outputs
# ==============================================================
write_verilog -noattr -noexpr -nohex ${OUT_DIR}/soc_top_netlist.v
write_json ${OUT_DIR}/soc_top.json

puts "=========================================="
puts " Full SoC Synthesis Complete"
puts " Netlist: ${OUT_DIR}/soc_top_netlist.v"
puts " Area:    ${RPT_DIR}/soc_top_area.rpt"
puts "=========================================="
