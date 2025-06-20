-include make_include.txt
SIM ?= verilator
TOPLEVEL_LANG ?= verilog
TEST_DIR := $(PWD)/..
VERILOG_SOURCES += $(TEST_DIR)/../fifo_sync.v

# Default values for fifo_sync parameters
DATA_WIDTH ?= 16
ADDR_WIDTH ?= 4
ALMOST_FULL_THRESHOLD ?= 2
ALMOST_EMPTY_THRESHOLD ?= 2

# Enable waveform dumping for Verilator, ignore warnings and set parameters for DUT, read from make_include.txt
# If the file does not exist, use default values
EXTRA_ARGS += --trace --trace-structs -Wno-fatal --timing \
	-pvalue+DATA_WIDTH=$(DATA_WIDTH) \
	-pvalue+ADDR_WIDTH=$(ADDR_WIDTH) \
	-pvalue+ALMOST_FULL_THRESHOLD=$(ALMOST_FULL_THRESHOLD) \
	-pvalue+ALMOST_EMPTY_THRESHOLD=$(ALMOST_EMPTY_THRESHOLD)

# Where the results will be stored
RESULTS_DIR := $(TEST_DIR)/results

# This is where the compiled simulator binaries and intermediate files are placed
SIM_BUILD := $(RESULTS_DIR)/sim_build

# This will place results.xml inside our results directory
COCOTB_RESULTS_FILE := $(RESULTS_DIR)/results.xml

# Phony targets (not real files)
.PHONY: test_custom_core clean_test

test_custom_core:
	mkdir -p $(RESULTS_DIR)
	COCOTB_RESULTS_FILE=$(COCOTB_RESULTS_FILE) SIM_BUILD=$(SIM_BUILD) \
		RESULTS_DIR=$(RESULTS_DIR) \
		$(MAKE) sim MODULE=fifo_sync_test TOPLEVEL=fifo_sync; \
	RESULT=$$?; \
	mv dump.vcd $(RESULTS_DIR)/dump.vcd; \
	if [ $$RESULT -ne 0 ]; then exit $$RESULT; fi

clean_test:
	rm -rf __pycache__ $(RESULTS_DIR)

include $(shell cocotb-config --makefiles)/Makefile.sim
