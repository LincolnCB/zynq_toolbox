-include hw_manager_test_setup.txt
SIM ?= verilator
TOPLEVEL_LANG ?= verilog
VERILOG_SOURCES += $(PWD)/../hw_manager.v

# Default values for hw_manager parameters
SHUTDOWN_FORCE_DELAY ?= 25000000
SHUTDOWN_RESET_PULSE  ?= 25000
SHUTDOWN_RESET_DELAY  ?= 25000000
BUF_LOAD_WAIT         ?= 25000000
SPI_START_WAIT        ?= 250000000 

# Enable waveform dumping for Verilator, ignore warnings and set parameters for DUT, read from hw_manager_test_setup.txt
# If the file does not exist, use default values
EXTRA_ARGS += --trace --trace-structs -Wno-fatal \
	-pvalue+SHUTDOWN_FORCE_DELAY=$(SHUTDOWN_FORCE_DELAY) \
	-pvalue+SHUTDOWN_RESET_PULSE=$(SHUTDOWN_RESET_PULSE) \
	-pvalue+SHUTDOWN_RESET_DELAY=$(SHUTDOWN_RESET_DELAY) \
	-pvalue+BUF_LOAD_WAIT=$(BUF_LOAD_WAIT) \
	-pvalue+SPI_START_WAIT=$(SPI_START_WAIT)

hw_manager_test:
	$(MAKE) sim MODULE=hw_manager_test TOPLEVEL=hw_manager

clean_test:
	rm -rf __pycache__ results.xml sim_build dump.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim