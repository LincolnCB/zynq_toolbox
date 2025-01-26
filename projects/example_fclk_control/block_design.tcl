## Instantiate the processing system and connect it to fixed IO and DDR

# Create the PS (processing_system7)
# 1: Use board preset
# Config:
# - Disable AXI ACP interface
# - Disable M_AXI_GP0 interface
# No connections
init_ps ps_0 1 {
  PCW_USE_S_AXI_ACP 0
  PCW_USE_M_AXI_GP0 0
} {
}
