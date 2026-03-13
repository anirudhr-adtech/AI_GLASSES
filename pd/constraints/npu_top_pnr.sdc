###############################################################################
# SDC Constraints — NPU Subsystem (npu_top) — PnR version
# Target: 100 MHz (10.0 ns period) on SKY130
# Note: 200 MHz SDC is for pre-CTS STA and SCL 180nm sign-off.
#       SKY130 PnR uses relaxed 100 MHz for achievable timing closure.
###############################################################################

# ----------------------------------------------------------------------
# Clock definition
# ----------------------------------------------------------------------
create_clock -name npu_clk -period 10.0 [get_ports clk]

# Clock uncertainty (jitter + skew budget)
set_clock_uncertainty 0.5 [get_clocks npu_clk]

# Clock transition constraint
set_clock_transition 0.25 [get_clocks npu_clk]

# ----------------------------------------------------------------------
# Input delays — AXI4-Lite slave interface (from CPU domain)
# Assume 40% of clock period for input setup
# ----------------------------------------------------------------------
set axilite_inputs [get_ports {s_axi_lite_awaddr* s_axi_lite_awvalid \
    s_axi_lite_wdata* s_axi_lite_wstrb* s_axi_lite_wvalid \
    s_axi_lite_bready \
    s_axi_lite_araddr* s_axi_lite_arvalid \
    s_axi_lite_rready}]

set_input_delay  -clock npu_clk -max 4.0 $axilite_inputs
set_input_delay  -clock npu_clk -min 1.0 $axilite_inputs

# ----------------------------------------------------------------------
# Output delays — AXI4-Lite slave interface (to CPU domain)
# ----------------------------------------------------------------------
set axilite_outputs [get_ports {s_axi_lite_awready \
    s_axi_lite_wready \
    s_axi_lite_bresp* s_axi_lite_bvalid \
    s_axi_lite_arready \
    s_axi_lite_rdata* s_axi_lite_rresp* s_axi_lite_rvalid}]

set_output_delay -clock npu_clk -max 4.0 $axilite_outputs
set_output_delay -clock npu_clk -min 1.0 $axilite_outputs

# ----------------------------------------------------------------------
# Input delays — AXI4 DMA master interface (from DDR/crossbar)
# ----------------------------------------------------------------------
set axi_dma_inputs [get_ports {m_axi_dma_awready \
    m_axi_dma_wready \
    m_axi_dma_bid* m_axi_dma_bresp* m_axi_dma_bvalid \
    m_axi_dma_arready \
    m_axi_dma_rid* m_axi_dma_rdata* m_axi_dma_rresp* \
    m_axi_dma_rlast m_axi_dma_rvalid}]

set_input_delay  -clock npu_clk -max 4.0 $axi_dma_inputs
set_input_delay  -clock npu_clk -min 1.0 $axi_dma_inputs

# ----------------------------------------------------------------------
# Output delays — AXI4 DMA master interface (to DDR/crossbar)
# ----------------------------------------------------------------------
set axi_dma_outputs [get_ports {m_axi_dma_awid* m_axi_dma_awaddr* \
    m_axi_dma_awlen* m_axi_dma_awsize* m_axi_dma_awburst* \
    m_axi_dma_awqos* m_axi_dma_awvalid \
    m_axi_dma_wdata* m_axi_dma_wstrb* m_axi_dma_wlast m_axi_dma_wvalid \
    m_axi_dma_bready \
    m_axi_dma_arid* m_axi_dma_araddr* m_axi_dma_arlen* \
    m_axi_dma_arsize* m_axi_dma_arburst* m_axi_dma_arqos* \
    m_axi_dma_arvalid \
    m_axi_dma_rready}]

set_output_delay -clock npu_clk -max 4.0 $axi_dma_outputs
set_output_delay -clock npu_clk -min 1.0 $axi_dma_outputs

# ----------------------------------------------------------------------
# Interrupt output
# ----------------------------------------------------------------------
set_output_delay -clock npu_clk -max 4.0 [get_ports irq_npu_done]
set_output_delay -clock npu_clk -min 1.0 [get_ports irq_npu_done]

# ----------------------------------------------------------------------
# Reset — async, false-path (reset tree buffered during CTS/PnR)
# ----------------------------------------------------------------------
set_input_delay -clock npu_clk -max 4.0 [get_ports rst_n]
set_input_delay -clock npu_clk -min 0.0 [get_ports rst_n]
set_false_path -from [get_ports rst_n]

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
