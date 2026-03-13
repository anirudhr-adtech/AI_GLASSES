###############################################################################
# SDC Constraints — DDR Wrapper (PnR)
# 100 MHz target for SKY130
###############################################################################

# Clock definition
create_clock -name sys_clk -period 10.0 [get_ports clk]
set_clock_uncertainty 0.5 [get_clocks sys_clk]
set_clock_transition 0.25 [get_clocks sys_clk]

# Input delays
set_input_delay -clock sys_clk -max 4.0 [all_inputs]
set_input_delay -clock sys_clk -min 1.0 [all_inputs]

# Output delays
set_output_delay -clock sys_clk -max 4.0 [all_outputs]
set_output_delay -clock sys_clk -min 1.0 [all_outputs]

# False path on reset
set_false_path -from [get_ports rst_n]

# Design constraints
set_max_transition 0.75 [current_design]
set_max_capacitance 0.3 [current_design]

# Driving cell and load
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 [all_inputs]
set_load 0.05 [all_outputs]
