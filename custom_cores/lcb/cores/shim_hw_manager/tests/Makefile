-include shim_hw_manager_test_setup.txt
SIM ?= verilator
TOPLEVEL_LANG ?= verilog
VERILOG_SOURCES += $(PWD)/../shim_hw_manager.v

# Default values for shim_hw_manager parameters
SHUTDOWN_FORCE_DELAY ?= 25000000
SHUTDOWN_RESET_PULSE  ?= 25000
SHUTDOWN_RESET_DELAY  ?= 25000000
SPI_INIT_WAIT         ?= 25000000
SPI_START_WAIT        ?= 250000000 

# Enable waveform dumping for Verilator, ignore warnings and set parameters for DUT, read from shim_hw_manager_test_setup.txt
# If the file does not exist, use default values
EXTRA_ARGS += --trace --trace-structs -Wno-fatal --timing \
	-pvalue+SHUTDOWN_FORCE_DELAY=$(SHUTDOWN_FORCE_DELAY) \
	-pvalue+SHUTDOWN_RESET_PULSE=$(SHUTDOWN_RESET_PULSE) \
	-pvalue+SHUTDOWN_RESET_DELAY=$(SHUTDOWN_RESET_DELAY) \
	-pvalue+SPI_INIT_WAIT=$(SPI_INIT_WAIT) \
	-pvalue+SPI_START_WAIT=$(SPI_START_WAIT)

# Where the results will be stored
RESULTS_ROOT_DIR := $(PWD)/results

# This is where the compiled simulator binaries and intermediate files are placed
SIM_BUILD := $(RESULTS_ROOT_DIR)/sim_build

# This will place results.xml inside our results directory
COCOTB_RESULTS_FILE := $(RESULTS_ROOT_DIR)/results.xml


shim_hw_manager_test:
	mkdir -p $(RESULTS_ROOT_DIR)
	COCOTB_RESULTS_FILE=$(COCOTB_RESULTS_FILE) SIM_BUILD=$(SIM_BUILD) \
	RESULTS_ROOT_DIR=$(RESULTS_ROOT_DIR) \
	$(MAKE) sim MODULE=shim_hw_manager_test TOPLEVEL=shim_hw_manager

clean_test:
	rm -rf __pycache__  $(RESULTS_ROOT_DIR) dump.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim