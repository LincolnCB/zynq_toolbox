-include latch_high_test_setup.txt
SIM ?= verilator
TOPLEVEL_LANG ?= verilog
VERILOG_SOURCES += $(PWD)/../latch_high.v

# Default values for latch_high parameters
WIDTH ?= 32

# Enable waveform dumping for Verilator, ignore warnings and set parameters for DUT, read from latch_high_test_setup.txt
# If the file does not exist, use default values
EXTRA_ARGS += --trace --trace-structs -Wno-fatal --timing \
	-pvalue+WIDTH=$(WIDTH)

# Where the results will be stored
RESULTS_ROOT_DIR := $(PWD)/results

# This is where the compiled simulator binaries and intermediate files are placed
SIM_BUILD := $(RESULTS_ROOT_DIR)/sim_build

# This will place results.xml inside our results directory
COCOTB_RESULTS_FILE := $(RESULTS_ROOT_DIR)/results.xml

latch_high_test:
	mkdir -p $(RESULTS_ROOT_DIR)
	COCOTB_RESULTS_FILE=$(COCOTB_RESULTS_FILE) SIM_BUILD=$(SIM_BUILD) \
	RESULTS_ROOT_DIR=$(RESULTS_ROOT_DIR) \
	$(MAKE) sim MODULE=latch_high_test TOPLEVEL=latch_high

clean_test:
	rm -rf __pycache__  $(RESULTS_ROOT_DIR) dump.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim