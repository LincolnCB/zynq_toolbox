# 'make' builds everything
# 'make clean' deletes everything except source files and Makefile
#
# You need to set NAME, PART and PROC for your project.
# NAME is the base name for most of the generated files.

# Variables to define the project, chip, and processor
NAME = adc_recorder_limited_cores
PART = xc7z010clg400-1
PROC = ps7_cortexa9_0

# Get the list of cores from the cores subdirectory in the project directory (which are symbolic links to the cores in the cores directory)
PROJECT_VERILOG_FILES = $(wildcard projects/$(NAME)/cores/*.v)
# Convert this list to a list of core names (e.g. "projects/$(NAME)/cores/uart.v" -> "cores/uart")
PROJECT_CORES = $(PROJECT_VERILOG_FILES:projects/$(NAME)/%.v=%)

# Get a list of all cores in the cores directory
ALL_VERILOG_FILES = $(wildcard cores/*.v)
# Convert this list to a list of core names (e.g. "cores/uart.v" -> "cores/uart")
ALL_CORES = $(ALL_VERILOG_FILES:.v=)

# Set up commands
VIVADO = vivado -nolog -nojournal -mode batch
XSCT = xsct
RM = rm -rf

# Files not to delete on completion (.PRECIOUS is a special target that tells make not to delete these files)
.PRECIOUS: tmp/cores/% tmp/%.xpr tmp/%.bit

# Default target (build everything)
all: tmp/$(NAME).bit boot.bin boot-rootfs.bin

# All the cores necessary for the project
cores: $(addprefix tmp/, $(PROJECT_CORES))

# The Xilinx project file
xpr: tmp/$(NAME).xpr

# The bitstream file
bit: tmp/$(NAME).bit

# Cores are built using the scripts/core.tcl script
tmp/cores/%: cores/%.v
	mkdir -p $(@D)
	$(VIVADO) -source scripts/core.tcl -tclargs $* $(PART)

# The project file requires all the cores
# Built using the scripts/project.tcl script
tmp/%.xpr: projects/% $(addprefix tmp/, $(PROJECT_CORES))
	mkdir -p $(@D)
	$(VIVADO) -source scripts/project.tcl -tclargs $* $(PART)

# The bitstream file requires the project file
# Built using the scripts/bitstream.tcl script
tmp/%.bit: tmp/%.xpr
	mkdir -p $(@D)
	$(VIVADO) -source scripts/bitstream.tcl -tclargs $*

# Remove the temporary files (including outputs!)
clean:
	$(RM) tmp
	$(RM) .Xil
