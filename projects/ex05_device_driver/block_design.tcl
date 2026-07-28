# No external FPGA ports are used in this project.
#
# This project builds TWO IDENTICAL register blocks in the PL. The hardware is
# deliberately the same in both cases -- the only thing that differs is which
# kernel driver binds to it, and therefore how userspace reaches it:
#
#   Block "uio"   0x40000000 (CFG) / 0x40100000 (STS)  -> simple-reg-uio kernel module
#   Block "cdev"  0x40200000 (CFG) / 0x40300000 (STS)  -> simple-reg-cdev kernel module
#
# Building both at once means you can insmod both drivers on a single boot and
# compare them directly (behaviour, permissions, and access latency) without
# rebuilding the bitstream in between.
#
# Each block is the same CFG -> NAND -> STS arrangement used in ex02:
# write two 32-bit words into the 64-bit CFG register, and read their bitwise
# NAND back out of the 32-bit STS register. That gives every driver a cheap,
# self-checking round trip through the PL: if the value you read back is the
# NAND of the two you wrote, the whole path is working.


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
#   - Four Manager/Master interfaces (CFG and STS for each of the two blocks)
#   - Connects to the processing system's GP AXI 0 interface, and clock, and the reset manager's reset
cell xilinx.com:ip:smartconnect:1.0 axi_smc {
  NUM_SI 1
  NUM_MI 4
} {
  aclk ps/FCLK_CLK0
  aresetn ps_rst/peripheral_aresetn
  S00_AXI /ps/M_AXI_GP0
}


############# Register blocks #############

# The two blocks are generated from a single loop so that it is structurally
# obvious they are the same hardware. `blocks` is a list of:
#   {name  cfg_offset  sts_offset  smc_cfg_port  smc_sts_port}
#
# Note on the address offsets: they are spaced 1 MiB apart, which is far more
# than the 128-byte minimum Vivado range. That is deliberate. The kernel maps
# memory to userspace with page granularity (4 KiB on this platform), so giving
# each register its own page means a UIO mapping of one register can never
# expose a neighbouring one. Packing them closer would work electrically but
# would undermine the whole point of the exercise.
set blocks {
  {uio  0x40000000 0x40100000 M00_AXI M01_AXI}
  {cdev 0x40200000 0x40300000 M02_AXI M03_AXI}
}

foreach block $blocks {
  lassign $block name cfg_offset sts_offset smc_cfg_port smc_sts_port

  ### Read/Write "CFG" config register
  ## Create a read/write register with an AXI4-Lite interface
  # - Config register width is 64 bits (two 32-bit words, both NAND inputs)
  # - Connect to the PS clock and the reset manager's reset
  # - Connect to the PS GP AXI 0 interface through the assigned SmartConnect port
  cell pavel-demin:user:axi_cfg_register cfg_$name {
    CFG_DATA_WIDTH 64
    AXI_ADDR_WIDTH 32
  } {
    aclk ps/FCLK_CLK0
    aresetn ps_rst/peripheral_aresetn
    S_AXI axi_smc/$smc_cfg_port
  }
  # Assign the address of the CFG register in the PS address space
  # - Range: 4K (one page -- see the note above)
  addr $cfg_offset 4K cfg_$name/S_AXI ps/M_AXI_GP0

  ### Read-only "STS" status register
  ## Create a read-only status register with an AXI4-Lite interface
  # - Status register width is 32 bits (the NAND result)
  cell pavel-demin:user:axi_sts_register sts_$name {
    STS_DATA_WIDTH 32
    AXI_ADDR_WIDTH 32
  } {
    aclk ps/FCLK_CLK0
    aresetn ps_rst/peripheral_aresetn
    S_AXI axi_smc/$smc_sts_port
  }
  # Assign the address of the STS register in the PS address space
  addr $sts_offset 4K sts_$name/S_AXI ps/M_AXI_GP0

  ### Vector NAND between the two halves of the CFG register
  # This command will source its code from the `modules/nand.tcl` file.
  # The 64-bit CFG word feeds straight in (no slicing needed, unlike ex02,
  # because here the CFG register is exactly the width the NAND wants), and the
  # 32-bit result feeds straight out to the STS register.
  module nand nand_$name {
    nand_din_concat cfg_$name/cfg_data
    nand_res        sts_$name/sts_data
  }
}
