 # cocotb variable -- Simulator to use (needs to match $(shell cocotb-config --makefiles)/simulators/Makefile.$(SIM))
SIM ?= verilator
# cocotb variable -- Top-level language (needs to match an option in the above-mentioned Makefile.$(SIM))
TOPLEVEL_LANG ?= verilog
# Core directory (two levels up from the tests/src directory where this Makefile is run)
CORE_DIR := $(abspath $(CURDIR)/../..)
# Directory containing the tests
TEST_DIR := $(CORE_DIR)/tests

# Name of the core, derived from the directory name
CORE_NAME := $(notdir $(CORE_DIR))
# cocotb variable -- Main Verilog source file for the core
VERILOG_SOURCES += $(CORE_DIR)/$(CORE_NAME).v
# cocotb variable -- Add additional Verilog sources from submodules
VERILOG_SOURCES += $(wildcard $(CORE_DIR)/submodules/*.v)

# Where the results of the simulation will be placed
RESULTS_DIR := $(TEST_DIR)/results
# cocotb variable -- Where the compiled simulator binaries and intermediate files are placed. Defaults to "sim_build"
SIM_BUILD := $(RESULTS_DIR)/sim_build
# cocotb variable -- Where the cocotb results will be stored. Defaults to "results.xml"
COCOTB_RESULTS_FILE := $(RESULTS_DIR)/results.xml

# Log some information about variables as they increment
$(info --------------------------)
$(info Variable checks (as make recurses):)
$(info -- $$(MAKELEVEL): $(MAKELEVEL))
ifeq ($(MAKELEVEL), 1) # Start at 1 because this Makefile will be loaded by a script run from the top-level Makefile
$(info -- Core name: $(CORE_NAME))
$(info -- Using Verilog sources: $(VERILOG_SOURCES))
endif
$(info -  "$(CURDIR)" is the $$CURDIR variable (current directory))
$(info -  "$(CORE_DIR)" is the $$CORE_DIR variable ($$(abspath $$(CURDIR)/../..)))
$(info -  "$(TEST_DIR)" is the $$TEST_DIR variable ($$(CORE_DIR)/tests))
$(info -  "$(firstword $(MAKEFILE_LIST))" is the top Makefile ($$(firstword $$(MAKEFILE_LIST))))
$(info --------------------------)

# Additional compile arguments, including Verilog core parameters (from parameters.json)
EXTRA_ARGS += --trace --trace-structs -Wno-fatal --timing 
# Parse parameters.json with jq and add as -pvalue+KEY=VALUE to EXTRA_ARGS
ifneq ("$(wildcard parameters.json)","")
EXTRA_ARGS += $(foreach kv,$(shell jq -r 'to_entries|map("\(.key)=\(.value|tostring)")|.[]' parameters.json),-pvalue+$(kv))
endif

$(info Using EXTRA_ARGS: $(EXTRA_ARGS))
$(info --------------------------)


# Phony targets (not real files)
.PHONY: test_custom_core clean_test

# Expects a cocotb module named <CORE_NAME>_test
test_custom_core:
	mkdir -p $(RESULTS_DIR)
	COCOTB_RESULTS_FILE=$(COCOTB_RESULTS_FILE) SIM_BUILD=$(SIM_BUILD) \
		RESULTS_DIR=$(RESULTS_DIR) \
		$(MAKE) --file="$(firstword $(MAKEFILE_LIST))" sim MODULE=testbench TOPLEVEL=$(CORE_NAME); \
	RESULT=$$?; \
	mv dump.vcd $(RESULTS_DIR)/dump.vcd; \
	rm -rf __pycache__; \
	if [ $$RESULT -ne 0 ]; then exit $$RESULT; fi

clean_test:
	rm -rf __pycache__ $(RESULTS_DIR)

# Include the cocotb Makefile (which includes the simulator-specific Makefile and a lot else)
include $(shell cocotb-config --makefiles)/Makefile.sim
