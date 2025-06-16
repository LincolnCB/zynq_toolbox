-include fifo_sync_test_setup.txt
SIM ?= verilator
TOPLEVEL_LANG ?= verilog
VERILOG_SOURCES += $(PWD)/../fifo_sync.v

# Default values for fifo_sync parameters
DATA_WIDTH ?= 16
ADDR_WIDTH ?= 4
ALMOST_FULL_THRESHOLD ?= 2
ALMOST_EMPTY_THRESHOLD ?= 2

# Enable waveform dumping for Verilator, ignore warnings and set parameters for DUT, read from fifo_sync_test_setup.txt
# If the file does not exist, use default values
EXTRA_ARGS += --trace --trace-structs -Wno-fatal --timing \
	-pvalue+DATA_WIDTH=$(DATA_WIDTH) \
	-pvalue+ADDR_WIDTH=$(ADDR_WIDTH) \
	-pvalue+ALMOST_FULL_THRESHOLD=$(ALMOST_FULL_THRESHOLD) \
	-pvalue+ALMOST_EMPTY_THRESHOLD=$(ALMOST_EMPTY_THRESHOLD) \

fifo_sync_test:
	$(MAKE) sim MODULE=fifo_sync_test TOPLEVEL=fifo_sync

clean_test:
	rm -rf __pycache__ results.xml sim_build dump.vcd fifo_sync_coverage.xml fifo_sync_coverage.yaml

include $(shell cocotb-config --makefiles)/Makefile.sim