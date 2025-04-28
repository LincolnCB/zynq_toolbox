############# General setup #############

## Instantiate the processing system

# Create the PS (processing_system7)
# Config:
# - Unused AXI ACP port disabled
# Connections:
# - GP AXI 0 (Master) clock is connected to the processing system's first clock, FCLK_CLK0
init_ps ps_0 {
  PCW_USE_S_AXI_ACP 0
} {
  M_AXI_GP0_ACLK ps_0/FCLK_CLK0
}