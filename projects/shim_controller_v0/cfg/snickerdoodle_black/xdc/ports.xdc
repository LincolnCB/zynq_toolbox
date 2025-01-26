###############################################################################
#
#   Constraints file for snickerdoodle black
#
#   Copyright (c) 2016 krtkl inc.
#
###############################################################################
#
#------------------------------------------------------------------------------
# STEMlab 125-14 Compatibility Constraints
#------------------------------------------------------------------------------

# Single-ended 10MHz clock input
# Pin: 10MHz_In JB2.38 N18
set_property IOSTANDARD LVCMOS25 [get_ports ext_clk_i]
set_property PULLTYPE PULLDOWN [get_ports ext_clk_i]
set_property PACKAGE_PIN N18 [get_ports ext_clk_i]

# Single-ended Trigger in
# Pin: Trigger_In JB2.36 P19
set_property IOSTANDARD LVCMOS25 [get_ports trigger_i]
set_property PULLTYPE PULLDOWN [get_ports trigger_i]
set_property PACKAGE_PIN P19 [get_ports trigger_i]

# SPI CS out, differential
# Pins: 
#   ~DAC_CS+O JB2.5 N17
#   ~DAC_CS-O JB2.7 P18
set_property IOSTANDARD LVDS_25 [get_ports cs_o_p]
set_property PACKAGE_PIN N17 [get_ports cs_o_p]
set_property IOSTANDARD LVDS_25 [get_ports cs_o_n]
set_property PACKAGE_PIN P18 [get_ports cs_o_n]

# SPI clock out, differential
# Pins:
#   ~SCKI+ JB2.23 T20
#   ~SCKI- JB2.25 U20
set_property IOSTANDARD LVDS_25 [get_ports spi_clk_o_p]
set_property PACKAGE_PIN T20 [get_ports spi_clk_o_p]
set_property IOSTANDARD LVDS_25 [get_ports spi_clk_o_n]
set_property PACKAGE_PIN U20 [get_ports spi_clk_o_n]


# SPI LDAC out, differential
# Pins:
#   ~LDAC+ JB2.26 V16
#   ~LDAC- JB2.24 W16
set_property IOSTANDARD LVDS_25 [get_ports ldac_o_p]
set_property PACKAGE_PIN V16 [get_ports ldac_o_p]
set_property IOSTANDARD LVDS_25 [get_ports ldac_o_n]
set_property PACKAGE_PIN W16 [get_ports ldac_o_n]

# SPI MOSI out (4 channels to DAC), differential
# Pins:
#   DAC_MOSI+0 JB2.20 W18
#   DAC_MOSI-0 JB2.18 W19
#   DAC_MOSI+1 JB1.5  T11
#   DAC_MOSI-1 JB1.7  T10
#   DAC_MOSI+2 JC1.11 T5
#   DAC_MOSI-2 JC1.13 U5
#   DAC_MOSI+3 JB1.23 T16
#   DAC_MOSI-3 JB1.25 U17
# Future:
#   DAC_MOSI+4 JA2.8  K16
#   DAC_MOSI-4 JA2.6  J16
#   DAC_MOSI+5 JA1.5  E18
#   DAC_MOSI-5 JA1.7  E19
#   DAC_MOSI+6 JA2.26 K19
#   DAC_MOSI-6 JA2.24 J19
#   DAC_MOSI+7 JA1.26 G19
#   DAC_MOSI-7 JA1.24 G20
set_property IOSTANDARD LVDS_25 [get_ports {dac_mosi_o_p[*]}]
set_property PACKAGE_PIN W18 [get_ports {dac_mosi_o_p[0]}]
set_property PACKAGE_PIN T11 [get_ports {dac_mosi_o_p[1]}]
set_property PACKAGE_PIN T5  [get_ports {dac_mosi_o_p[2]}]
set_property PACKAGE_PIN T16 [get_ports {dac_mosi_o_p[3]}]
set_property IOSTANDARD LVDS_25 [get_ports {dac_mosi_o_n[*]}]
set_property PACKAGE_PIN W19 [get_ports {dac_mosi_o_n[0]}]
set_property PACKAGE_PIN T10 [get_ports {dac_mosi_o_n[1]}]
set_property PACKAGE_PIN U5  [get_ports {dac_mosi_o_n[2]}]
set_property PACKAGE_PIN U17 [get_ports {dac_mosi_o_n[3]}]

# # AXI clock out, single-ended (DEBUG)
# # Pin:
# #   AXI_CLK_OUT JB2.4 R19
# set_property IOSTANDARD LVCMOS25 [get_ports axi_clk_out]
# set_property PACKAGE_PIN R19 [get_ports axi_clk_out]
