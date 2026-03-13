###############################################################################
# SDC Constraints — Camera Subsystem (cam_subsys_top) — PnR version
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
# DVP pixel clock — separate domain, false-path to sys_clk
# ----------------------------------------------------------------------
create_clock -name pclk -period 20.0 [get_ports cam_pclk_i]
set_clock_uncertainty 0.5 [get_clocks pclk]
set_clock_transition 0.25 [get_clocks pclk]

# CDC between pclk and sys_clk — handled by synchronizers in RTL
set_false_path -from [get_clocks pclk] -to [get_clocks sys_clk]
set_false_path -from [get_clocks sys_clk] -to [get_clocks pclk]

# ----------------------------------------------------------------------
# Input delays — DVP camera interface (pclk domain)
# ----------------------------------------------------------------------
set dvp_inputs [get_ports {cam_vsync_i cam_href_i cam_data_i*}]

set_input_delay  -clock pclk -max 8.0 $dvp_inputs
set_input_delay  -clock pclk -min 2.0 $dvp_inputs

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
# Input delays — AXI4 VDMA master interface (from DDR/crossbar)
# ----------------------------------------------------------------------
set axi_vdma_inputs [get_ports {m_axi_vdma_awready \
    m_axi_vdma_wready \
    m_axi_vdma_bid* m_axi_vdma_bresp* m_axi_vdma_bvalid \
    m_axi_vdma_arready \
    m_axi_vdma_rid* m_axi_vdma_rdata* m_axi_vdma_rresp* \
    m_axi_vdma_rlast m_axi_vdma_rvalid}]

set_input_delay  -clock sys_clk -max 4.0 $axi_vdma_inputs
set_input_delay  -clock sys_clk -min 1.0 $axi_vdma_inputs

# ----------------------------------------------------------------------
# Output delays — AXI4 VDMA master interface (to DDR/crossbar)
# ----------------------------------------------------------------------
set axi_vdma_outputs [get_ports {m_axi_vdma_awid* m_axi_vdma_awaddr* \
    m_axi_vdma_awlen* m_axi_vdma_awsize* m_axi_vdma_awburst* \
    m_axi_vdma_awvalid \
    m_axi_vdma_wdata* m_axi_vdma_wstrb* m_axi_vdma_wlast m_axi_vdma_wvalid \
    m_axi_vdma_bready \
    m_axi_vdma_arid* m_axi_vdma_araddr* m_axi_vdma_arlen* \
    m_axi_vdma_arsize* m_axi_vdma_arburst* m_axi_vdma_arvalid \
    m_axi_vdma_rready}]

set_output_delay -clock sys_clk -max 4.0 $axi_vdma_outputs
set_output_delay -clock sys_clk -min 1.0 $axi_vdma_outputs

# ----------------------------------------------------------------------
# Interrupt output
# ----------------------------------------------------------------------
set_output_delay -clock sys_clk -max 4.0 [get_ports irq_camera_ready_o]
set_output_delay -clock sys_clk -min 1.0 [get_ports irq_camera_ready_o]

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
