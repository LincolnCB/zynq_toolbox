SIM ?= verilator
TOPLEVEL_LANG ?= verilog
TEST_DIR := $(shell pwd)/..

CORE_NAME := $(notdir $(abspath $(TEST_DIR)/..))
VERILOG_SOURCES += $(abspath $(TEST_DIR)/../$(CORE_NAME).v)
VERILOG_SOURCES += $(abspath $(wildcard $(TEST_DIR)/../submodules/*.v))

$(info --------------------------)
$(info Core name: $(CORE_NAME))
$(info Using Verilog sources: $(VERILOG_SOURCES))
$(info $(TEST_DIR) is the test directory)
$(info --------------------------)

EXTRA_ARGS += --trace --trace-structs -Wno-fatal --timing 
# Parse parameters.json and add as -pvalue+KEY=VALUE to EXTRA_ARGS
ifneq ("$(wildcard parameters.json)","")
EXTRA_ARGS += $(foreach kv,$(shell jq -r 'to_entries|map("\(.key)=\(.value|tostring)")|.[]' parameters.json),-pvalue+$(kv))
endif

$(info --------------------------)
$(info Using EXTRA_ARGS: $(EXTRA_ARGS))
$(info --------------------------)

# Where the results will be stored
RESULTS_DIR := $(TEST_DIR)/results

# This is where the compiled simulator binaries and intermediate files are placed
SIM_BUILD := $(RESULTS_DIR)/sim_build

# This will place results.xml inside our results directory
COCOTB_RESULTS_FILE := $(RESULTS_DIR)/results.xml

# Phony targets (not real files)
.PHONY: test_custom_core clean_test

# Expects a cocotb module named <CORE_NAME>_test
test_custom_core:
	mkdir -p $(RESULTS_DIR)
	COCOTB_RESULTS_FILE=$(COCOTB_RESULTS_FILE) SIM_BUILD=$(SIM_BUILD) \
		RESULTS_DIR=$(RESULTS_DIR) \
		$(MAKE) sim MODULE=$(CORE_NAME)_test TOPLEVEL=$(CORE_NAME); \
	RESULT=$$?; \
	mv dump.vcd $(RESULTS_DIR)/dump.vcd; \
	if [ $$RESULT -ne 0 ]; then exit $$RESULT; fi

clean_test:
	rm -rf __pycache__ $(RESULTS_DIR)

include $(shell cocotb-config --makefiles)/Makefile.sim
