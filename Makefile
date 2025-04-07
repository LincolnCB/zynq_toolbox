#############################################
## Variables
#############################################
## Required environment variable inputs to the Makefile
#############################################

# You need to set PROJECT, BOARD, and BOARD_VERto the project and board you want to build
# These can be set on the command line:
# - e.g. 'make PROJECT=example_axi_hub_regs BOARD=snickerdoodle_black BOARD_VER=1.0'

# Default values for PROJECT and BOARD
PROJECT ?= example_axi_hub
BOARD ?= snickerdoodle_black
BOARD_VER ?= 1.0

#############################################



#############################################
## Initialization
#############################################
## Some scripts to initialize the environment and check for necessary tools/src
#############################################

# Check for the REV D environment variable
ifneq ($(shell pwd),$(REV_D_DIR))
$(warning Environment variable REV_D_DIR does not match the current directory)
$(warning - Current directory: $(shell pwd))
$(error - REV_D_DIR: $(REV_D_DIR))
endif

# Check if the target is only clean or clean_all (to avoid unnecessary checks)
CLEAN_ONLY = false
ifneq ($(),$(MAKECMDGOALS))
ifeq ($(),$(filter-out clean clean_all,$(MAKECMDGOALS)))
CLEAN_ONLY = true
endif
endif

$(info --------------------------)
$(info ---- Making "$(MAKECMDGOALS)")

# Run some checks and setup, but only if there are targets other than clean or clean_all
ifneq (true, $(CLEAN_ONLY)) # Clean check
$(info ----  for project "$(PROJECT)" and board "$(BOARD)" version $(BOARD_VER))

# Check the board, board version, and project
ifneq ($(), $(shell ./scripts/check/project.sh $(BOARD) $(BOARD_VER) $(PROJECT)))
$(info --------------------------)
$(info ----  Project check failed)
$(info ----  $(shell ./scripts/check/project.sh $(BOARD) $(BOARD_VER) $(PROJECT)))
$(info --------------------------)
$(error Missing sources)
endif

# Extract the part from board file
export PART=$(shell ./scripts/make/get_part.sh $(BOARD) $(BOARD_VER))
$(info ----  Part: $(PART))

# Get the list of necessary cores from the project file to avoid building unnecessary cores
PROJECT_CORES = $(shell ./scripts/make/get_cores_from_tcl.sh projects/$(PROJECT)/block_design.tcl)
BOARD_XDC = $(wildcard projects/$(PROJECT)/cfg/$(BOARD)/$(BOARD_VER)/xdc/*.xdc)
$(info --------------------------)
$(info ---- Project cores found using `scripts/make/get_cores_from_tcl.sh projects/$(PROJECT)/block_design.tcl`:)
$(info ----   $(PROJECT_CORES))
$(info --------------------------)
$(info ---- XDC files found in `projects/$(PROJECT)/cfg/$(BOARD)/$(BOARD_VER)/xdc/`:)
$(info ----   $(BOARD_XDC))



endif # Clean check
$(info --------------------------)

# Set up commands
VIVADO = vivado -nolog -nojournal -mode batch
XSCT = xsct
RM = rm -rf

#############################################



#############################################
## Make-specific targets (clean, all, .PHONY, etc.)
#############################################

# Files not to delete on half-completion (GNU Make 4.9)
.PRECIOUS: tmp/cores/% tmp/%.xpr tmp/%.bit

# Targets that aren't real files (GNU Make 4.9)
.PHONY: all clean clean_project clean_all bit sd rootfs boot cores xpr xsa

# Enable secondary expansion (GNU Make 3.9) to allow for more complex pattern matching (see cores target)
.SECONDEXPANSION:

# Default target is the first listed (GNU Make 2.3)
all: sd

# Remove a single project's intermediate and temporary files, including cores
clean_project:
	@./scripts/make/status.sh "CLEANING PROJECT: $(BOARD)/$(BOARD_VER)/$(PROJECT)"
	$(RM) tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)
	$(RM) -r $(addsuffix *, $(addprefix tmp/cores/, $(PROJECT_CORES)))

# Remove all the intermediate and temporary files
clean:
	@./scripts/make/status.sh "CLEANING"
	$(RM) .Xil
	$(RM) tmp

# Remove all the output files too
clean_all: clean
	@./scripts/make/status.sh "CLEANING OUTPUT FILES"
	$(RM) out

#############################################


#############################################
## Custom output targets (the important output stages)
#############################################

# All the files necessary for a bootable SD card. See PetaLinux UG1144 for info
# https://docs.amd.com/r/en-US/ug1144-petalinux-tools-reference-guide/Preparing-the-SD-Card
sd: boot rootfs

# The bitstream file (system.bit)
# Built from the Vivado project (project.xpr)
bit: tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)/bitstream.bit
	mkdir -p out/$(BOARD)/$(BOARD_VER)/$(PROJECT)
	cp tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)/bitstream.bit out/$(BOARD)/$(BOARD_VER)/$(PROJECT)/system.bit

# The compressed root filesystem
# Made in the petalinux build
rootfs: tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)/petalinux/images/linux/rootfs.tar.gz
	mkdir -p out/$(BOARD)/$(BOARD_VER)/$(PROJECT)
	cp tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)/petalinux/images/linux/rootfs.tar.gz out/$(BOARD)/$(BOARD_VER)/$(PROJECT)/rootfs.tar.gz

# The compressed boot files
# Requires the petalinux build (which will make the rootfs)
boot: tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)/petalinux/images/linux/rootfs.tar.gz
	mkdir -p out/$(BOARD)/$(BOARD_VER)/$(PROJECT)
	@./scripts/make/status.sh "PACKAGING BOOT.BIN"
	cd tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)/petalinux && \
		source $(PETALINUX_PATH)/settings.sh && \
		petalinux-package --boot \
		--format BIN \
		--fsbl \
		--fpga \
		--kernel \
		--boot-device sd \
		--force
	tar -czf out/$(BOARD)/$(BOARD_VER)/$(PROJECT)/BOOT.tar.gz \
		-C tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)/petalinux/images/linux \
		BOOT.BIN \
		image.ub \
		boot.scr \
		system.dtb


#############################################


#############################################
## Custom intermediate targets (could be used directly for testing)
#############################################

# All the cores necessary for the project
# Separated in `tmp/cores` by vendor
# The necessary cores for the specific project are extracted
# 	from `block_design.tcl` (recursively by sub-modules)
#		by `scripts/make/get_cores_from_tcl.sh`
cores: $(addprefix tmp/cores/, $(PROJECT_CORES))

# The Xilinx project file
# This file can be edited in Vivado to test TCL commands and changes
xpr: tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)/project.xpr

# The hardware definition file
# This file is used by petalinux to build the linux system
xsa: tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)/hw_def.xsa

#############################################



#############################################
## Specific targets (don't recommend using these directly)
#############################################

# Core RTL needs to be packaged to be used in the block design flow
# Cores are packaged using the `scripts/vivado/package_core.tcl` script
# This make target uses "pattern-specific variables" (GNU Make 6.12) to set the vendor and core
#  as well as "secondary expansion" (GNU Make 3.9) to allow for their use in the prerequisite
tmp/user_cores/%: VENDOR = $(word 1,$(subst /, ,$*))
tmp/user_cores/%: CORE = $(word 2,$(subst /, ,$*))
tmp/user_cores/%: user_cores/$$(VENDOR)/cores/$$(CORE)/$$(CORE).v
	@./scripts/make/status.sh "MAKING USER CORE: '$(CORE)' by '$(VENDOR)'"
	mkdir -p $(@D)
	$(VIVADO) -source scripts/vivado/package_core.tcl -tclargs $(VENDOR) $(CORE) $(PART)

# The project file (.xpr)
# Requires all the cores
# Built using the `scripts/vivado/project.tcl` script, which uses
# 	the block design and ports files from the project
tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)/project.xpr: projects/$(PROJECT)/block_design.tcl projects/$(PROJECT)/ports.tcl $(BOARD_XDC) $(addprefix tmp/user_cores/, $(PROJECT_CORES))
	@./scripts/make/status.sh "MAKING PROJECT: $(BOARD)/$(BOARD_VER)/$(PROJECT)/project.xpr"
	mkdir -p $(@D)
	$(VIVADO) -source scripts/vivado/project.tcl -tclargs $(BOARD) $(BOARD_VER) $(PROJECT)

# The bitstream file (.bit)
# Requires the project file
# Built using the `scripts/vivado/bitstream.tcl` script, with bitstream compression set to false
tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)/bitstream.bit: tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)/project.xpr
	@./scripts/make/status.sh "MAKING BITSTREAM: $(BOARD)/$(BOARD_VER)/$(PROJECT)/bitstream.bit"
	$(VIVADO) -source scripts/vivado/bitstream.tcl -tclargs $(BOARD)/$(BOARD_VER)/$(PROJECT) false

# The hardware definition file
# Requires the project file
# Built using the scripts/vivado/hw_def.tcl script
tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)/hw_def.xsa: tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)/project.xpr
	@./scripts/make/status.sh "MAKING HW DEF: $(BOARD)/$(BOARD_VER)/$(PROJECT)/hw_def.xsa"
	$(VIVADO) -source scripts/vivado/hw_def.tcl -tclargs $(BOARD)/$(BOARD_VER)/$(PROJECT)

# The compressed root filesystem
# Requires the hardware definition file
# Build using the scripts/petalinux/build.sh file
tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)/petalinux/images/linux/rootfs.tar.gz: tmp/$(BOARD)/$(BOARD_VER)/$(PROJECT)/hw_def.xsa
	@./scripts/make/status.sh "MAKING LINUX SYSTEM: $(BOARD)/$(BOARD_VER)/$(PROJECT)/petalinux"
	source $(PETALINUX_PATH)/settings.sh && \
		scripts/petalinux/build.sh $(BOARD) $(BOARD_VER) $(PROJECT)

