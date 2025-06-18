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

# Where the results will be stored
RESULTS_ROOT_DIR := $(PWD)/results

# This is where the compiled simulator binaries and intermediate files are placed
SIM_BUILD := $(RESULTS_ROOT_DIR)/sim_build

# This will place results.xml inside our results directory
COCOTB_RESULTS_FILE := $(RESULTS_ROOT_DIR)/results.xml

fifo_sync_test:
	mkdir -p $(RESULTS_ROOT_DIR)
	COCOTB_RESULTS_FILE=$(COCOTB_RESULTS_FILE) SIM_BUILD=$(SIM_BUILD) \
	RESULTS_ROOT_DIR=$(RESULTS_ROOT_DIR) \
	$(MAKE) sim MODULE=fifo_sync_test TOPLEVEL=fifo_sync

clean_test:
	rm -rf __pycache__  $(RESULTS_ROOT_DIR) dump.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim