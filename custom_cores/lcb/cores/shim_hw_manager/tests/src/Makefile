-include make_include.txt
SIM ?= verilator
TOPLEVEL_LANG ?= verilog
TEST_DIR := $(PWD)/..
VERILOG_SOURCES += $(TEST_DIR)/../shim_hw_manager.v

# Default values for shim_hw_manager parameters
SHUTDOWN_FORCE_DELAY  ?= 25000000
SHUTDOWN_RESET_PULSE  ?= 25000
SHUTDOWN_RESET_DELAY  ?= 25000000
SPI_RESET_WAIT        ?= 25000000
SPI_START_WAIT        ?= 250000000 

# Enable waveform dumping for Verilator, ignore warnings and set parameters for DUT, read from make_include.txt
# If the file does not exist, use default values
EXTRA_ARGS += --trace --trace-structs -Wno-fatal --timing \
	-pvalue+SHUTDOWN_FORCE_DELAY=$(SHUTDOWN_FORCE_DELAY) \
	-pvalue+SHUTDOWN_RESET_PULSE=$(SHUTDOWN_RESET_PULSE) \
	-pvalue+SHUTDOWN_RESET_DELAY=$(SHUTDOWN_RESET_DELAY) \
	-pvalue+SPI_RESET_WAIT=$(SPI_RESET_WAIT) \
	-pvalue+SPI_START_WAIT=$(SPI_START_WAIT)

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
		$(MAKE) sim MODULE=shim_hw_manager_test TOPLEVEL=shim_hw_manager; \
	RESULT=$$?; \
	mv dump.vcd $(RESULTS_DIR)/dump.vcd; \
	if [ $$RESULT -ne 0 ]; then exit $$RESULT; fi

clean_test:
	rm -rf __pycache__ $(RESULTS_DIR)

include $(shell cocotb-config --makefiles)/Makefile.sim
