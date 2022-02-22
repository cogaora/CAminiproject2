proc AddWaves {} {
	;#Add waves we're interested in to the Wave window
    add wave -position end sim:/cache_tb/clk
    add wave -position end sim:/cache_tb/s_reset
}

vlib work

;# Compile components if any
vcom memory.vhd
vcom memory_tb.vhd

;#vcom cache.vhd
;#vcom cache_tb.vhd

;# Start simulation
vsim memory_tb

;# Run for 1000 ns
run 1000ns
