# Single-ended clock (for scanner sync)
create_bd_port -dir I ext_clk_i
# Single-ended trigger
create_bd_port -dir I trigger_i

# Differential ports
create_bd_port -dir O cs_o_p
create_bd_port -dir O cs_o_n
create_bd_port -dir O spi_clk_o_n
create_bd_port -dir O spi_clk_o_p
create_bd_port -dir O ldac_o_p
create_bd_port -dir O ldac_o_n
create_bd_port -dir O -from 3 -to 0 dac_mosi_o_p
create_bd_port -dir O -from 3 -to 0 dac_mosi_o_n

# # AXI clock out (DEBUG)
# create_bd_port -dir O axi_clk_out

# (~Shutdown_Force)
create_bd_port -dir O n_Shutdown_Force
# (~Shutdown_Reset)
create_bd_port -dir O n_Shutdown_Reset


# Create processing system
init_ps ps_0 {
  PCW_USE_S_AXI_ACP 0
  PCW_UART1_PERIPHERAL_ENABLE 1
  PCW_UART1_UART1_IO {MIO 36 .. 37}
  PCW_UART1_BAUD_RATE 921600
  PCW_MIO_36_PULLUP enabled
  PCW_MIO_37_PULLUP enabled
} {
  M_AXI_GP0_ACLK ps_0/FCLK_CLK0
}

# Create xlconstant (default value 1) to hold reset high (active low)
cell xilinx.com:ip:xlconstant const_1
# Create proc_sys_reset
cell xilinx.com:ip:proc_sys_reset:5.0 rst_0 {} {
  ext_reset_in const_1/dout
}

## LCB: Make single-ended input for snickerdoodle
# Create clk_wiz
cell xilinx.com:ip:clk_wiz:6.0 mmcm_0 {
  PRIMITIVE MMCM
  PRIM_SOURCE Single_ended_clock_capable_pin
  PRIM_IN_FREQ.VALUE_SRC USER
  PRIM_IN_FREQ 10.0
  MMCM_REF_JITTER1 0.0005
  CLKOUT1_USED true
  CLKOUT1_REQUESTED_OUT_FREQ 50.0
  CLKOUT2_USED false
  USE_PHASE_ALIGNMENT true
  JITTER_SEL Min_O_Jitter
  JITTER_OPTIONS PS
  USE_DYN_RECONFIG false
} {
  clk_in1 ext_clk_i
}

# create a block of memory of 256KB, which would consume 56 of the 60 36Kbit memory blocks available in the Z7010
cell xilinx.com:ip:blk_mem_gen:8.4 gradient_memory_0 {
  MEMORY_TYPE Simple_Dual_Port_RAM
  USE_BRAM_BLOCK Stand_Alone
  WRITE_WIDTH_A 32
  WRITE_DEPTH_A 65536
  WRITE_WIDTH_B 32
  ENABLE_A Always_Enabled
  ENABLE_B Always_Enabled
  REGISTER_PORTB_OUTPUT_OF_MEMORY_PRIMITIVES false
}

# Create axi_bram_writer for gradient waveform
cell pavel-demin:user:axi_bram_writer:1.0 gradient_writer_0 {
  AXI_DATA_WIDTH 32
  AXI_ADDR_WIDTH 32
  BRAM_DATA_WIDTH 32
  BRAM_ADDR_WIDTH 16
} {
  BRAM_PORTA gradient_memory_0/BRAM_PORTA
}
# Create all required interconnections on AXI bus for waveform writer
auto_connect_axi 0x40000000 256K gradient_writer_0/S_AXI /ps_0/M_AXI_GP0


# Create the shim_dac controller (spi sequencer)
module shim_dacs shim_dac_0 {
  spi_sequencer_0/BRAM_PORT0 gradient_memory_0/BRAM_PORTB
}
# Create all required interconnections on AXI bus for shim_dac controller
auto_connect_axi 0x40201000 4K shim_dac_0/spi_sequencer_0/S_AXI /ps_0/M_AXI_GP0


# Create an AXI bus config register
# this should not be needed at all, but makes it easy right now to provide some
# triggers
cell pavel-demin:user:axi_cfg_register:1.0 cfg_0 {
  CFG_DATA_WIDTH 64
  AXI_ADDR_WIDTH 32
  AXI_DATA_WIDTH 32
}
# Create all required interconnections
auto_connect_axi 0x40200000 4K cfg_0/S_AXI /ps_0/M_AXI_GP0

# LCB: Slice off bits 0 and 32 from the config register
cell xilinx.com:ip:xlslice:1.0 n_shutdown_force_slice {
  DIN_WIDTH 64 DIN_FROM 0 DIN_TO 0
} {
  din cfg_0/cfg_data
  dout n_Shutdown_Force
}
cell xilinx.com:ip:xlslice:1.0 shutdown_reset_slice {
  DIN_WIDTH 64 DIN_FROM 32 DIN_TO 32
} {
  din cfg_0/cfg_data
}
# Invert just the reset signal, so the initial 0s in the cfg register mean shutdown and no reset
cell xilinx.com:ip:util_vector_logic shutdown_reset_inv {
  C_SIZE 1
  C_OPERATION not
} {
  Op1 shutdown_reset_slice/dout
  Res n_Shutdown_Reset
}


# # Manually connect the MMCM to the PS
# apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {
#     Clk_master {/ps_0/FCLK_CLK0 (142 MHz)}
#     Clk_slave {Auto}
#     Clk_xbar {/ps_0/FCLK_CLK0 (142 MHz)}
#     Master {/ps_0/M_AXI_GP0}
#     Slave {/mmcm_0/s_axi_lite}
#     intc_ip {/ps_0_axi_periph}
#     master_apm {0}
# }  [get_bd_intf_pins mmcm_0/s_axi_lite]

# # seems like by default this is mapped to 0x43c00000/64K

# # set the address map for the MMCM, note for this interface the basename is "Reg" not "reg0"
# set_property RANGE 64K [get_bd_addr_segs ps_0/Data/SEG_mmcm_0_Reg]
# set_property OFFSET 0x43C00000 [get_bd_addr_segs ps_0/Data/SEG_mmcm_0_Reg]

# Create trigger core
cell open-mri:user:axi_trigger_core:1.0 trigger_core_0 {
  C_S_AXI_DATA_WIDTH 32
  C_S_AXI_ADDR_WIDTH 12
} {
  aclk /ps_0/FCLK_CLK0
  aresetn /rst_0/peripheral_aresetn
}
# Create all required interconnections on AXI bus for trigger core
auto_connect_axi 0x40202000 4K trigger_core_0/S_AXI /ps_0/M_AXI_GP0

# The RAM for the gradients should not have wait states?
set_property -dict [list CONFIG.Register_PortB_Output_of_Memory_Primitives {true} CONFIG.Register_PortB_Output_of_Memory_Core {false}] [get_bd_cells gradient_memory_0]

# the gradient DAC trigger pulse
connect_bd_net [get_bd_pins trigger_core_0/trigger_out] [get_bd_pins shim_dac_0/spi_sequencer_0/waveform_trigger]
connect_bd_net [get_bd_pins trigger_i] [get_bd_pins trigger_core_0/trigger_in]

# Hook up the SPI reference clock
wire shim_dac_0/spi_sequencer_0/spi_ref_clk ps_0/FCLK_CLK0


## Connect output buffers

# Differential output buffer for CS
cell lcb:user:differential_out_buffer:1.0 cs_o_buf {
  DIFF_BUFFER_WIDTH 1
} {
  d_in /shim_dac_0/spi_sequencer_0/spi_cs
  diff_out_p cs_o_p
  diff_out_n cs_o_n
}
# Differential output buffer for SPI clock
cell lcb:user:differential_out_buffer:1.0 spi_clk_o_buf {
  DIFF_BUFFER_WIDTH 1
} {
  d_in /shim_dac_0/spi_sequencer_0/spi_clk
  diff_out_p spi_clk_o_p
  diff_out_n spi_clk_o_n
}
# Differential output buffer for LDAC
# Invert the signal first
cell xilinx.com:ip:util_vector_logic ldac_inv {
  C_SIZE 1
  C_OPERATION not
} {
  Op1 /shim_dac_0/spi_sequencer_0/spi_ldacn
}
cell lcb:user:differential_out_buffer:1.0 ldac_o_buf {
  DIFF_BUFFER_WIDTH 1
} {
  d_in ldac_inv/Res
  diff_out_p ldac_o_p
  diff_out_n ldac_o_n
}
# Differential output buffer for DAC MOSI
cell lcb:user:differential_out_buffer:1.0 dac_mosi_o_buf {
  DIFF_BUFFER_WIDTH 4
} {
  d_in /shim_dac_0/spiconcat_0/Dout
  diff_out_p dac_mosi_o_p
  diff_out_n dac_mosi_o_n
}

# ## LCB: Add output port for AXI clock
# wire axi_clk_out ps_0/FCLK_CLK0
