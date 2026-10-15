create_clock -name board_clk -period 20 [get_ports {clk}]
derive_clocks
