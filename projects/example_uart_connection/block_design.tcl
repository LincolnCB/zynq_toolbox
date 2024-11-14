## Instantiate the processing system and connect it to fixed IO and DDR

# Create the PS (processing_system7)
# 1: Use board preset
# - Disable unneccessary M_AXI_GP0 and S_AXI_ACP interface
# - Enable and assign UART1
# - Enable pull-up resistors for the UART1 pins
# No connections necessary, this is a PS-focused project
init_ps ps_0 1 {
  PCW_USE_M_AXI_GP0 0
  PCW_USE_S_AXI_ACP 0
  PCW_UART1_PERIPHERAL_ENABLE 1
  PCW_UART1_UART1_IO {MIO 36 .. 37}
  PCW_MIO_36_PULLUP enabled
  PCW_MIO_37_PULLUP enabled
} {}
