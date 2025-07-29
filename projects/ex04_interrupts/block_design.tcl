# No external FPGA ports are used in this project.

## Instantiate the processing system

# Create the PS (processing_system7)
# Config:
# - Unused AXI ACP port disabled (or it will complain that the port's clock is not connected)
# Connections:
# - GP AXI 0 (Master) clock is connected to the processing system's first clock, FCLK_CLK0
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

## AXI SmartConnect for AXI interface
cell xilinx.com:ip:smartconnect:1.0 axi_smc {
  NUM_SI 1
  NUM_MI 1
} {
  aclk ps/FCLK_CLK0
  aresetn ps_rst/peripheral_aresetn
  S00_AXI /ps/M_AXI_GP0
}


## CFG register
# 64 adressable bits
cell pavel-demin:user:axi_cfg_register axi_irq {
  DATA_WIDTH 64
  ADDR_WIDTH 32
} {
  aclk ps/FCLK_CLK0
  aresetn ps_rst/peripheral_aresetn
  S_AXI axi_smc/M00_AXI
}
# Assign the address of the axi_irq in the PS address space
addr 0x40000000 128 axi_irq/S_AXI ps/M_AXI_GP0

# IRQ concat (necessary for the IRQ to work properly)
# cell xilinx.com:ip:xlconcat:2.1 irq_concat {
#   NUM_PORTS 8
# } {}
cell xilinx.com:ip:xlconcat:2.1 irq_concat {
  NUM_PORTS 8
} {
  dout ps/IRQ_F2P
}

# Slice 4 bits of the first 32 bits of the CFG register, 4 of the second
for {set i 0} {$i < 4} {incr i} {
  cell xilinx.com:ip:xlslice:1.0 irq_slice_${i} {
    DIN_WIDTH 64 DIN_FROM ${i} DIN_TO ${i}
  } {
    din axi_irq/cfg_data
    dout irq_concat/In${i}
  }
}
for {set i 4} {$i < 8} {incr i} {
  cell xilinx.com:ip:xlslice:1.0 irq_slice_${i} {
    DIN_WIDTH 64 DIN_FROM [expr {$i - 4 + 32}] DIN_TO [expr {$i - 4 + 32}]
  } {
    din axi_irq/cfg_data
    dout irq_concat/In${i}
  }
}
