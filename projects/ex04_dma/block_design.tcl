############# General setup #############

## Instantiate the processing system

# Create the PS (processing_system7)
# Config:
# - Unused AXI ACP port disabled
# Connections:
# - GP AXI 0 (Master) clock is connected to the processing system's first clock, FCLK_CLK0
init_ps ps {
  PCW_USE_S_AXI_ACP 0
  PCW_USE_S_AXI_HP0 1
} {
  M_AXI_GP0_ACLK ps/FCLK_CLK0
  S_AXI_HP0_ACLK ps/FCLK_CLK0
}

## PS reset core
# Create proc_sys_reset
cell xilinx.com:ip:proc_sys_reset:5.0 ps_rst {} {
  ext_reset_in ps/FCLK_RESET0_N
  slowest_sync_clk ps/FCLK_CLK0
}

### AXI Smart Connect cores
# PS-peripheral interconnect
cell xilinx.com:ip:smartconnect:1.0 axi_ps_periph_intercon {
  NUM_SI 1
  NUM_MI 1
} {
  aclk ps/FCLK_CLK0
  S00_AXI /ps/M_AXI_GP0
  aresetn ps_rst/peripheral_aresetn
}
# AXI memory interconnect
cell xilinx.com:ip:smartconnect:1.0 axi_mem_intercon {
  NUM_SI 2
  NUM_MI 1
} {
  aclk ps/FCLK_CLK0
  M00_AXI ps/S_AXI_HP0
  aresetn ps_rst/peripheral_aresetn
}

# Create the AXI DMA core
cell xilinx.com:ip:axi_dma:7.1 axi_dma {
  c_enable_multi_channel 0
  c_include_sg 0
  c_sg_include_stscntrl_strm 0
} {
  s_axi_lite_aclk ps/FCLK_CLK0
  m_axi_mm2s_aclk ps/FCLK_CLK0
  m_axi_s2mm_aclk ps/FCLK_CLK0
  axi_resetn ps_rst/peripheral_aresetn
  S_AXI_LITE axi_ps_periph_intercon/M00_AXI
  M_AXI_MM2S axi_mem_intercon/S00_AXI
  M_AXI_S2MM axi_mem_intercon/S01_AXI
}
## Set addresses (these match the automation, but is better to have explicit)
# Set the DMA control address
addr 0x40400000 64k axi_dma/S_AXI_LITE ps/M_AXI_GP0
# Set the AXI_HP memory addresses
addr 0x00000000 1G ps/S_AXI_HP0 axi_dma/M_AXI_MM2S
addr 0x00000000 1G ps/S_AXI_HP0 axi_dma/M_AXI_S2MM

# Interrupt concat (necessary)
cell xilinx.com:ip:xlconcat:2.1 intr_concat {
  NUM_PORTS 2
} {
  In0 axi_dma/mm2s_introut
  In1 axi_dma/s2mm_introut
  dout ps/IRQ_F2P
}
# AXIS loopback
cell xilinx.com:ip:axis_data_fifo:2.0 axis_loopback {} {
  S_AXIS axi_dma/M_AXIS_MM2S
  M_AXIS axi_dma/S_AXIS_S2MM
  s_axis_aresetn ps_rst/peripheral_aresetn
  s_axis_aclk ps/FCLK_CLK0
}
