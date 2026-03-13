###############################################################################
# SDC Constraints — Audio Subsystem (audio_subsys_top) — PnR version
# Target: 100 MHz (10.0 ns period) on SKY130
###############################################################################

# ----------------------------------------------------------------------
# Clock definition
# ----------------------------------------------------------------------
create_clock -name sys_clk -period 10.0 [get_ports clk_i]

# Clock uncertainty (jitter + skew budget)
set_clock_uncertainty 0.5 [get_clocks sys_clk]

# Clock transition constraint
set_clock_transition 0.25 [get_clocks sys_clk]

# ----------------------------------------------------------------------
# Input delays — I2S interface (external codec)
# I2S signals are slow relative to sys_clk, generous timing
# ----------------------------------------------------------------------
set i2s_inputs [get_ports {i2s_sck_i i2s_ws_i i2s_sd_i}]

set_input_delay  -clock sys_clk -max 4.0 $i2s_inputs
set_input_delay  -clock sys_clk -min 1.0 $i2s_inputs

# ----------------------------------------------------------------------
# Input delays — AXI4-Lite slave interface (from CPU domain)
# Assume 40% of clock period for input setup
# ----------------------------------------------------------------------
set axilite_inputs [get_ports {s_axi_lite_awaddr* s_axi_lite_awvalid \
    s_axi_lite_wdata* s_axi_lite_wstrb* s_axi_lite_wvalid \
    s_axi_lite_bready \
    s_axi_lite_araddr* s_axi_lite_arvalid \
    s_axi_lite_rready}]

set_input_delay  -clock sys_clk -max 4.0 $axilite_inputs
set_input_delay  -clock sys_clk -min 1.0 $axilite_inputs

# ----------------------------------------------------------------------
# Output delays — AXI4-Lite slave interface (to CPU domain)
# ----------------------------------------------------------------------
set axilite_outputs [get_ports {s_axi_lite_awready \
    s_axi_lite_wready \
    s_axi_lite_bresp* s_axi_lite_bvalid \
    s_axi_lite_arready \
    s_axi_lite_rdata* s_axi_lite_rresp* s_axi_lite_rvalid}]

set_output_delay -clock sys_clk -max 4.0 $axilite_outputs
set_output_delay -clock sys_clk -min 1.0 $axilite_outputs

# ----------------------------------------------------------------------
# Input delays — AXI4 DMA master interface (from DDR/crossbar)
# Audio DMA is write-only (no AR/R channels)
# ----------------------------------------------------------------------
set axi_dma_inputs [get_ports {m_axi_dma_awready \
    m_axi_dma_wready \
    m_axi_dma_bid* m_axi_dma_bresp* m_axi_dma_bvalid}]

set_input_delay  -clock sys_clk -max 4.0 $axi_dma_inputs
set_input_delay  -clock sys_clk -min 1.0 $axi_dma_inputs

# ----------------------------------------------------------------------
# Output delays — AXI4 DMA master interface (to DDR/crossbar)
# Audio DMA is write-only (no AR/R channels)
# ----------------------------------------------------------------------
set axi_dma_outputs [get_ports {m_axi_dma_awid* m_axi_dma_awaddr* \
    m_axi_dma_awlen* m_axi_dma_awsize* m_axi_dma_awburst* \
    m_axi_dma_awvalid \
    m_axi_dma_wdata* m_axi_dma_wstrb* m_axi_dma_wlast m_axi_dma_wvalid \
    m_axi_dma_bready}]

set_output_delay -clock sys_clk -max 4.0 $axi_dma_outputs
set_output_delay -clock sys_clk -min 1.0 $axi_dma_outputs

# ----------------------------------------------------------------------
# Interrupt output
# ----------------------------------------------------------------------
set_output_delay -clock sys_clk -max 4.0 [get_ports irq_audio_ready_o]
set_output_delay -clock sys_clk -min 1.0 [get_ports irq_audio_ready_o]

# ----------------------------------------------------------------------
# Reset — async, false-path (reset tree buffered during CTS/PnR)
# ----------------------------------------------------------------------
set_input_delay -clock sys_clk -max 4.0 [get_ports rst_ni]
set_input_delay -clock sys_clk -min 0.0 [get_ports rst_ni]
set_false_path -from [get_ports rst_ni]

# ----------------------------------------------------------------------
# Max transition / max capacitance
# ----------------------------------------------------------------------
set_max_transition 0.75 [current_design]
set_max_capacitance 0.3 [current_design]

# ----------------------------------------------------------------------
# Driving cell and load
# ----------------------------------------------------------------------
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 [all_inputs]
set_load 0.05 [all_outputs]
