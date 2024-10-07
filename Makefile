# 'make' builds everything
# 'make clean' deletes everything except source files and Makefile
#
# You need to set PROJECT and BOARD to the project and board you want to build
# These can be set on the command line, e.g. 'make PROJECT=adc_recorder BOARD=snickerdoodle_black'

# Default values for PROJECT and BOARD
PROJECT ?= adc_recorder
BOARD ?= snickerdoodle_black

# Run some checks and setup, but only if the target isn't just 'clean'
ifneq (clean,$(filter clean,$(MAKECMDGOALS))) ### CLEAN CHECK

# Check that the project and board exist, and that the necessary files are present
ifeq (,$(wildcard boards/$(BOARD)/board_config.json))
$(error Board "$(BOARD)" or the corresponding board configuration file "boards/$(BOARD)/board_config.json" does not exist)
endif
ifeq (,$(wildcard projects/$(PROJECT)))
$(error Project "$(PROJECT)" does not exist)
endif
ifeq (,$(wildcard projects/$(PROJECT)/block_design.tcl))
$(error Project "$(PROJECT)" does not have a block design file "projects/$(PROJECT)/block_design.tcl")
endif
ifeq (,$(wildcard projects/$(PROJECT)/ports.tcl))
$(error Project "$(PROJECT)" does not have a ports file "projects/$(PROJECT)/ports.tcl")
endif
ifeq (,$(wildcard projects/$(PROJECT)/$(BOARD)/ports.xdc))
$(error No support for board "$(BOARD)" in project "$(PROJECT)" -- "projects/$(PROJECT)/$(BOARD)/ports.xdc" missing)
endif


# Extract the part and processor from the board configuration file
export PART=$(shell jq -r '.HDL.part' boards/$(BOARD)/board_config.json)
export PROC=$(shell jq -r '.HDL.proc' boards/$(BOARD)/board_config.json)

# Get the list of cores from the project file
PROJECT_CORES = $(shell ./scripts/get_cores_from_tcl.sh projects/$(PROJECT)/block_design.tcl)
VENDOR_LIST = $(shell ./scripts/get_vendors_from_cores.sh "$(PROJECT_CORES)")

endif ########################################## CLEAN CHECK

# Set up commands
VIVADO = vivado -nolog -nojournal -mode batch
XSCT = xsct
RM = rm -rf

# Files not to delete on half-completion (.PRECIOUS is a special target that tells make not to delete these files)
.PRECIOUS: tmp/cores/% tmp/%.xpr tmp/%.bit

# Default target (build everything)
all: tmp/$(BOARD)_$(PROJECT).bit

# All the cores necessary for the project
cores: $(addprefix tmp/cores/, $(PROJECT_CORES))

# The Xilinx project file
xpr: tmp/$(BOARD)_$(PROJECT).xpr

# The bitstream file
bit: tmp/$(BOARD)_$(PROJECT).bit

# Cores are built using the scripts/package_core.tcl script
tmp/cores/%: cores/%.v
	mkdir -p $(@D)
	$(VIVADO) -source scripts/package_core.tcl -tclargs $* $(PART)

# The project file requires all the cores
# Built using the scripts/project.tcl script
tmp/$(BOARD)_$(PROJECT).xpr: projects/$(PROJECT) $(addprefix tmp/cores/, $(PROJECT_CORES))
	mkdir -p $(@D)
	$(VIVADO) -source scripts/project.tcl -tclargs $* $(PROJECT) $(BOARD) {$(VENDOR_LIST)}

# The bitstream file requires the project file
# Built using the scripts/bitstream.tcl script
tmp/%.bit: tmp/%.xpr
	mkdir -p $(@D)
	$(VIVADO) -source scripts/bitstream.tcl -tclargs $*

# Remove the temporary files (including outputs!)
clean:
	$(RM) tmp
	$(RM) .Xil
