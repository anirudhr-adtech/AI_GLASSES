###############################################################################
# SDC Constraints — Full SoC (soc_top)
# 4 clock domains: sys_clk (100 MHz), npu_clk (200 MHz),
#                  cam_pclk (~24 MHz, async), i2s_sck (<1 MHz, async)
###############################################################################

# ==============================================================
# Clock definitions
# ==============================================================

# System clock — 100 MHz (10 ns period)
create_clock -name sys_clk -period 10.0 [get_ports sys_clk_i]

# NPU clock — 200 MHz (5 ns period)
create_clock -name npu_clk -period 5.0 [get_ports npu_clk_i]

# Camera PCLK — 24 MHz (41.67 ns period), async external
create_clock -name cam_pclk -period 41.67 [get_ports cam_pclk_i]

# I2S serial clock — 1.536 MHz (651 ns period), async external
create_clock -name i2s_sck -period 651.0 [get_ports i2s_sck_i]

# ==============================================================
# Clock uncertainty
# ==============================================================
set_clock_uncertainty 0.25 [get_clocks sys_clk]
set_clock_uncertainty 0.25 [get_clocks npu_clk]
set_clock_uncertainty 0.50 [get_clocks cam_pclk]
set_clock_uncertainty 0.50 [get_clocks i2s_sck]

# ==============================================================
# Clock groups — async domains (no paths to analyze between groups)
# ==============================================================
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks cam_pclk] \
    -group [get_clocks i2s_sck]

# NPU clock is related to sys_clk (both from Zynq PLL, 2:1 ratio)
# But CDC exists at NPU boundary — use set_max_delay for CDC paths
# set_clock_groups -asynchronous -group [get_clocks npu_clk] -group [get_clocks sys_clk]

# ==============================================================
# Reset input — false path (reset tree buffered during CTS/PnR)
# ==============================================================
set_input_delay -clock sys_clk -max 3.0 [get_ports sys_rst_ni]
set_input_delay -clock sys_clk -min 0.0 [get_ports sys_rst_ni]
set_false_path -from [get_ports sys_rst_ni]

# Internal reset distribution — high-fanout reset FFs will get buffer tree in CTS
# False-path reset synchronizer outputs and recovery/removal checks
set_false_path -through [get_pins -filter "lib_pin_name == RESET_B" -of_objects [get_cells -filter "ref_name == sky130_fd_sc_hd__dfrtp_1"]]
# False-path all paths through isolation/power-gating cells (reset distribution)
# These high-fanout nets will get proper buffer trees during CTS/PnR
set_false_path -through [get_pins */X -filter "lib_pin_name == X" -of_objects [get_cells -filter "ref_name =~ sky130_fd_sc_hd__lpflow_*"]]

# ==============================================================
# AXI3 HP0 interface — to Zynq DDR controller
# All signals in sys_clk domain
# ==============================================================
set hp0_inputs [get_ports {m_axi_hp0_awready \
    m_axi_hp0_wready \
    m_axi_hp0_bid* m_axi_hp0_bresp* m_axi_hp0_bvalid \
    m_axi_hp0_arready \
    m_axi_hp0_rid* m_axi_hp0_rdata* m_axi_hp0_rresp* \
    m_axi_hp0_rlast m_axi_hp0_rvalid}]

set_input_delay  -clock sys_clk -max 4.0 $hp0_inputs
set_input_delay  -clock sys_clk -min 1.0 $hp0_inputs

set hp0_outputs [get_ports {m_axi_hp0_awid* m_axi_hp0_awaddr* \
    m_axi_hp0_awlen* m_axi_hp0_awsize* m_axi_hp0_awburst* \
    m_axi_hp0_awqos* m_axi_hp0_awvalid \
    m_axi_hp0_wdata* m_axi_hp0_wstrb* m_axi_hp0_wlast m_axi_hp0_wvalid \
    m_axi_hp0_bready \
    m_axi_hp0_arid* m_axi_hp0_araddr* m_axi_hp0_arlen* \
    m_axi_hp0_arsize* m_axi_hp0_arburst* m_axi_hp0_arqos* \
    m_axi_hp0_arvalid \
    m_axi_hp0_rready}]

set_output_delay -clock sys_clk -max 4.0 $hp0_outputs
set_output_delay -clock sys_clk -min 1.0 $hp0_outputs

# ==============================================================
# UART — sys_clk domain
# ==============================================================
set_output_delay -clock sys_clk -max 5.0 [get_ports uart_tx_o]
set_output_delay -clock sys_clk -min 0.0 [get_ports uart_tx_o]
set_input_delay  -clock sys_clk -max 5.0 [get_ports uart_rx_i]
set_input_delay  -clock sys_clk -min 0.0 [get_ports uart_rx_i]

# ==============================================================
# Camera DVP — cam_pclk domain
# ==============================================================
set cam_inputs [get_ports {cam_vsync_i cam_href_i cam_data_i*}]
set_input_delay  -clock cam_pclk -max 10.0 $cam_inputs
set_input_delay  -clock cam_pclk -min 2.0  $cam_inputs

# ==============================================================
# I2S Audio — i2s_sck domain
# ==============================================================
set_input_delay  -clock i2s_sck -max 100.0 [get_ports {i2s_ws_i i2s_sd_i}]
set_input_delay  -clock i2s_sck -min 10.0  [get_ports {i2s_ws_i i2s_sd_i}]

# ==============================================================
# SPI — sys_clk domain (internally generated SCLK)
# ==============================================================
set spi_outputs [get_ports {spi_sclk_o spi_mosi_o spi_cs_n_o}]
set_output_delay -clock sys_clk -max 5.0 $spi_outputs
set_output_delay -clock sys_clk -min 0.0 $spi_outputs
set_input_delay  -clock sys_clk -max 5.0 [get_ports spi_miso_i]
set_input_delay  -clock sys_clk -min 0.0 [get_ports spi_miso_i]

# ==============================================================
# I2C — sys_clk domain (open-drain with tristate)
# ==============================================================
set i2c_outputs [get_ports {i2c_scl_o i2c_scl_oe_o i2c_sda_o i2c_sda_oe_o}]
set i2c_inputs  [get_ports {i2c_scl_i i2c_sda_i}]
set_output_delay -clock sys_clk -max 5.0 $i2c_outputs
set_output_delay -clock sys_clk -min 0.0 $i2c_outputs
set_input_delay  -clock sys_clk -max 5.0 $i2c_inputs
set_input_delay  -clock sys_clk -min 0.0 $i2c_inputs

# ==============================================================
# GPIO — sys_clk domain
# ==============================================================
set_input_delay  -clock sys_clk -max 5.0 [get_ports gpio_i*]
set_input_delay  -clock sys_clk -min 0.0 [get_ports gpio_i*]
set_output_delay -clock sys_clk -max 5.0 [get_ports {gpio_o* gpio_oe*}]
set_output_delay -clock sys_clk -min 0.0 [get_ports {gpio_o* gpio_oe*}]

# ==============================================================
# ESP32 handshake
# ==============================================================
set_input_delay  -clock sys_clk -max 5.0 [get_ports esp32_handshake_i]
set_input_delay  -clock sys_clk -min 0.0 [get_ports esp32_handshake_i]
set_output_delay -clock sys_clk -max 5.0 [get_ports esp32_reset_n_o]
set_output_delay -clock sys_clk -min 0.0 [get_ports esp32_reset_n_o]

# ==============================================================
# Max transition / capacitance
# ==============================================================
set_max_transition 0.75 [current_design]
set_max_capacitance 0.3 [current_design]

# ==============================================================
# Driving cell and output load
# ==============================================================
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_4 [all_inputs]
set_load 0.1 [all_outputs]
