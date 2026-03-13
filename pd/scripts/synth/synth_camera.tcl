###############################################################################
# Yosys Synthesis Script — Camera Subsystem (cam_subsys_top)
# Target: SKY130 HD standard cells
# Usage:  yosys -c scripts/synth/synth_camera.tcl   (run from pd/ directory)
###############################################################################

yosys -import

set TOP        cam_subsys_top
set LIB_DIR    $::env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib
set LIB_TT    ${LIB_DIR}/sky130_fd_sc_hd__tt_025C_1v80.lib
set OUT_DIR    results/synth
set RPT_DIR    results/synth

file mkdir $OUT_DIR
file mkdir $RPT_DIR

# --- Read RTL (all 18 camera modules, bottom-up order) ---
read_verilog ../rtl/camera/gray_counter.v
read_verilog ../rtl/camera/pixel_fifo.v
read_verilog ../rtl/camera/dvp_sync.v
read_verilog ../rtl/camera/dvp_capture.v
read_verilog ../rtl/camera/yuv2rgb.v
read_verilog ../rtl/camera/isp_lite.v
read_verilog ../rtl/camera/line_buffer.v
read_verilog ../rtl/camera/resize_engine.v
read_verilog ../rtl/camera/crop_engine.v
read_verilog ../rtl/camera/crop_resize.v
read_verilog ../rtl/camera/pixel_packer.v
read_verilog ../rtl/camera/crop_dma_reader.v
read_verilog ../rtl/camera/crop_dma_writer.v
read_verilog ../rtl/camera/frame_buf_ctrl.v
read_verilog ../rtl/camera/video_dma.v
read_verilog ../rtl/camera/cam_regfile.v
read_verilog ../rtl/camera/cam_controller.v
read_verilog ../rtl/camera/cam_subsys_top.v

# --- Use the standard synth command (handles flatten + opt + tech map) ---
synth -top $TOP -flatten

# --- Technology mapping to SKY130 ---
dfflibmap -liberty $LIB_TT
abc -liberty $LIB_TT -D 10000

# --- Clean up ---
opt_clean -purge

# --- Reports ---
tee -o ${RPT_DIR}/cam_subsys_top_area.rpt stat -liberty $LIB_TT
tee -o ${RPT_DIR}/cam_subsys_top_check.rpt check

# --- Write outputs ---
write_verilog -noattr -noexpr -nohex ${OUT_DIR}/cam_subsys_top_netlist.v
write_json ${OUT_DIR}/cam_subsys_top.json

puts "=========================================="
puts " Camera Synthesis Complete"
puts " Netlist: ${OUT_DIR}/cam_subsys_top_netlist.v"
puts " Area:    ${RPT_DIR}/cam_subsys_top_area.rpt"
puts "=========================================="
