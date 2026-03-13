# SDC constraints — RISC-V Subsystem (riscv_subsys_top)
# 100 MHz target (10ns period) for SKY130

create_clock -name clk -period 10.0 [get_ports clk_i]
set_clock_uncertainty 0.5 [get_clocks clk]

# Input/output delays
set_input_delay  -clock clk -max 4.0 [all_inputs]
set_input_delay  -clock clk -min 1.0 [all_inputs]
set_output_delay -clock clk -max 4.0 [all_outputs]
set_output_delay -clock clk -min 1.0 [all_outputs]

# Reset is async — false path
set_false_path -from [get_ports rst_ni]
