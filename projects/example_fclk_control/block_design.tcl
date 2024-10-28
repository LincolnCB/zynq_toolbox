## Instantiate the processing system and connect it to fixed IO and DDR

# Create the PS (processing_system7)
# 0: Don't use board preset
# - Disable M_AXI_GP0 interface
# - Connect the FCLK_CLK0 to external pin for scoping
init_ps ps_0 0 {
  PCW_USE_M_AXI_GP0 0
} {
  FCLK_CLK0 fclk0
}
