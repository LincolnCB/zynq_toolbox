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
  aresetn ps_rst/peripheral_aresetn
  S00_AXI ps/M_AXI_GP0
}
# AXI memory interconnect
cell xilinx.com:ip:smartconnect:1.0 axi_mem_intercon {
  NUM_SI 3
  NUM_MI 1
} {
  aclk ps/FCLK_CLK0
  aresetn ps_rst/peripheral_aresetn
  M00_AXI ps/S_AXI_HP0
}

# Create the AXI Multi-channel DMA core
cell xilinx.com:ip:axi_mcdma:1.2 axi_mcdma {
  c_num_mm2s_channels 8
  c_num_s2mm_channels 8
} {
  s_axi_aclk ps/FCLK_CLK0
  s_axi_lite_aclk ps/FCLK_CLK0
  axi_resetn ps_rst/peripheral_aresetn
  S_AXI_LITE axi_ps_periph_intercon/M00_AXI
  M_AXI_MM2S axi_mem_intercon/S00_AXI
  M_AXI_S2MM axi_mem_intercon/S01_AXI
  M_AXI_SG axi_mem_intercon/S02_AXI
}
## Set addresses (these match the automation, but is better to have explicit)
# Set the DMA control address
addr 0x40400000 64k axi_mcdma/S_AXI_LITE ps/M_AXI_GP0
# Set the AXI_HP memory addresses
addr 0x00000000 1G ps/S_AXI_HP0 axi_mcdma/M_AXI_MM2S
addr 0x00000000 1G ps/S_AXI_HP0 axi_mcdma/M_AXI_S2MM
addr 0x00000000 1G ps/S_AXI_HP0 axi_mcdma/M_AXI_SG

# Interrupt concat (necessary)
cell xilinx.com:ip:xlconcat:2.1 intr_concat {
  NUM_PORTS 16
} {
  In0  axi_mcdma/mm2s_ch1_introut
  In1  axi_mcdma/s2mm_ch1_introut
  In2  axi_mcdma/mm2s_ch2_introut
  In3  axi_mcdma/s2mm_ch2_introut
  In4  axi_mcdma/mm2s_ch3_introut
  In5  axi_mcdma/s2mm_ch3_introut
  In6  axi_mcdma/mm2s_ch4_introut
  In7  axi_mcdma/s2mm_ch4_introut
  In8  axi_mcdma/mm2s_ch5_introut
  In9  axi_mcdma/s2mm_ch5_introut
  In10 axi_mcdma/mm2s_ch6_introut
  In11 axi_mcdma/s2mm_ch6_introut
  In12 axi_mcdma/mm2s_ch7_introut
  In13 axi_mcdma/s2mm_ch7_introut
  In14 axi_mcdma/mm2s_ch8_introut
  In15 axi_mcdma/s2mm_ch8_introut
  dout ps/IRQ_F2P
}
# AXIS Broadcaster
cell xilinx.com:ip:axis_broadcaster:1.1 axis_broadcaster {
  NUM_MI 8
} {
  aclk ps/FCLK_CLK0
  aresetn ps_rst/peripheral_aresetn
  S_AXIS axi_mcdma/M_AXIS_MM2S
}
# AXIS Combiner
cell xilinx.com:ip:axis_combiner:1.1 axis_combiner {
  NUM_SI 8
} {
  aclk ps/FCLK_CLK0
  aresetn ps_rst/peripheral_aresetn
  M_AXIS axi_mcdma/S_AXIS_S2MM
}

# Eight channels of loopback
for {set i 0} {$i < 8} {incr i} {
  cell xilinx.com:ip:axis_data_fifo:2.0 axis_loopback_$i {} {
    S_AXIS axis_broadcaster/M0${i}_AXIS
    M_AXIS axis_combiner/S0${i}_AXIS
    s_axis_aresetn ps_rst/peripheral_aresetn
    s_axis_aclk ps/FCLK_CLK0
  }
}
