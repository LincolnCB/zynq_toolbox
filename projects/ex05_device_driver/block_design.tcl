# No external FPGA ports are used in this project.
#
# This project builds ONE register block in the PL and drives it from a custom
# kernel device driver (simple-reg), so userspace can reach the registers
# directly (mmap, full speed) but WITHOUT root -- the thing /dev/mem cannot do.
#
#   CFG 0x40000000  /  STS 0x40100000   -> simple-reg kernel module -> /dev/simple-reg
#
# The block is the same CFG -> NAND -> STS arrangement used in ex02:
# write two 32-bit words into the 64-bit CFG register, and read their bitwise
# NAND back out of the 32-bit STS register. That gives a cheap, self-checking
# round trip through the PL: if the value you read back is the NAND of the two
# you wrote, the whole path (driver, mmap, PL) is working.
#
# CFG and STS sit on separate, non-adjacent pages on purpose: the driver maps
# each independently, which mirrors how real designs (e.g. the Rev D Shim)
# scatter register banks across the address map.


############# General setup #############

## Instantiate the processing system
# Config:
# - Unused AXI ACP port disabled (or it will complain that the port's clock is not connected)
# Connections:
# - GP AXI 0 (Manager) clock is connected to the processing system's first clock, FCLK_CLK0
init_ps ps {
  PCW_USE_S_AXI_ACP 0
} {
  M_AXI_GP0_ACLK ps/FCLK_CLK0
}


## Create the reset manager
# Create proc_sys_reset
# - Resetn is constant low (active high)
cell xilinx.com:ip:proc_sys_reset ps_rst {} {
  ext_reset_in ps/FCLK_RESET0_N
  slowest_sync_clk ps/FCLK_CLK0
}


############# AXI interconnect #############

### AXI4 SmartConnect to branch to multiple AXI4 interfaces
#   - One Subordinate/Slave interface (from the PS)
#   - Two Manager/Master interfaces (CFG and STS)
#   - Connects to the processing system's GP AXI 0 interface, and clock, and the reset manager's reset
cell xilinx.com:ip:smartconnect:1.0 axi_smc {
  NUM_SI 1
  NUM_MI 2
} {
  aclk ps/FCLK_CLK0
  aresetn ps_rst/peripheral_aresetn
  S00_AXI /ps/M_AXI_GP0
}


############# Register block #############

# One block: CFG -> NAND -> STS. CFG and STS get their own 4 KiB page and are
# spaced 1 MiB apart. The kernel maps memory to userspace with page
# granularity (4 KiB here), so each register living on its own page means a
# mapping of one can never expose the other. They are non-adjacent on purpose:
# the driver maps each independently, mirroring real scattered register maps.

### Read/Write "CFG" config register
## Create a read/write register with an AXI4-Lite interface
# - Config register width is 64 bits (two 32-bit words, both NAND inputs)
# - Connect to the PS clock and the reset manager's reset
# - Connect to the PS GP AXI 0 interface through SmartConnect port M00
cell pavel-demin:user:axi_cfg_register cfg {
  CFG_DATA_WIDTH 64
  AXI_ADDR_WIDTH 32
} {
  aclk ps/FCLK_CLK0
  aresetn ps_rst/peripheral_aresetn
  S_AXI axi_smc/M00_AXI
}
# Assign the address of the CFG register in the PS address space
# - Range: 4K (one page -- see the note above)
addr 0x40000000 4K cfg/S_AXI ps/M_AXI_GP0

### Read-only "STS" status register
## Create a read-only status register with an AXI4-Lite interface
# - Status register width is 32 bits (the NAND result)
cell pavel-demin:user:axi_sts_register sts {
  STS_DATA_WIDTH 32
  AXI_ADDR_WIDTH 32
} {
  aclk ps/FCLK_CLK0
  aresetn ps_rst/peripheral_aresetn
  S_AXI axi_smc/M01_AXI
}
# Assign the address of the STS register in the PS address space
addr 0x40100000 4K sts/S_AXI ps/M_AXI_GP0

### Vector NAND between the two halves of the CFG register
# This command will source its code from the `modules/nand.tcl` file.
# The 64-bit CFG word feeds straight in (no slicing needed, unlike ex02,
# because here the CFG register is exactly the width the NAND wants), and the
# 32-bit result feeds straight out to the STS register.
module nand_block nand_block {
  nand_din_concat cfg/cfg_data
  nand_res        sts/sts_data
}
