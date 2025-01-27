# ## This file is a general .xdc for the Zybo Z7 Rev. B
# ## It is compatible with the Zybo Z7-20 and Zybo Z7-10
# ## To use it in a project:
# ## - uncomment the lines corresponding to used pins
# ## - rename the used ports (in each line, after get_ports) according to the top level signal names in the project

# ## Clock signal
# create_bd_port -dir I -type clk sysclk

# ## Switches
# create_bd_port -dir I -from 3 -to 0 sw

# ## Buttons
# create_bd_port -dir I -from 3 -to 0 btn

# ## LEDs
# create_bd_port -dir O -from 3 -to 0 led

# ## RGB LED 5 (Zybo Z7-20 only)
# create_bd_port -dir O led5_r
# create_bd_port -dir O led5_g
# create_bd_port -dir O led5_b

# ## RGB LED 6
# create_bd_port -dir O led6_r
# create_bd_port -dir O led6_g
# create_bd_port -dir O led6_b

# ## Audio Codec
# create_bd_port -dir O ac_bclk
# create_bd_port -dir O ac_mclk
# create_bd_port -dir O ac_muten
# create_bd_port -dir O ac_pbdat
# create_bd_port -dir O ac_pblrc
# create_bd_port -dir I ac_recdat
# create_bd_port -dir O ac_reclrc
# create_bd_port -dir O ac_scl
# create_bd_port -dir IO ac_sda

# ## Additional Ethernet signals
# create_bd_port -dir O eth_int_pu_b
# create_bd_port -dir O eth_rst_b

# ## USB-OTG over-current detect pin
# create_bd_port -dir I otg_oc

# ## Fan (Zybo Z7-20 only)
# create_bd_port -dir O fan_fb_pu

# ## HDMI RX
# create_bd_port -dir O hdmi_rx_hpd
# create_bd_port -dir O hdmi_rx_scl
# create_bd_port -dir IO hdmi_rx_sda
# create_bd_port -dir O hdmi_rx_clk_n
# create_bd_port -dir O hdmi_rx_clk_p
# create_bd_port -dir O -from 2 -to 0 hdmi_rx_n
# create_bd_port -dir O -from 2 -to 0 hdmi_rx_p

# ## HDMI RX CEC (Zybo Z7-20 only)
# create_bd_port -dir O hdmi_rx_cec

# ## HDMI TX
# create_bd_port -dir O hdmi_tx_hpd
# create_bd_port -dir O hdmi_tx_scl
# create_bd_port -dir IO hdmi_tx_sda
# create_bd_port -dir O hdmi_tx_clk_n
# create_bd_port -dir O hdmi_tx_clk_p
# create_bd_port -dir O -from 2 -to 0 hdmi_tx_n
# create_bd_port -dir O -from 2 -to 0 hdmi_tx_p

# ## HDMI TX CEC
# create_bd_port -dir O hdmi_tx_cec

# ## Pmod Header JA (XADC)
# create_bd_port -dir IO -from 7 -to 0 ja

# ## Pmod Header JB (Zybo Z7-20 only)
# create_bd_port -dir IO -from 7 -to 0 jb

# ## Pmod Header JC
# create_bd_port -dir IO -from 7 -to 0 jc

# ## Pmod Header JD
# create_bd_port -dir IO -from 7 -to 0 jd

# ## Pmod Header JE
# create_bd_port -dir IO -from 7 -to 0 je

# ## Pcam MIPI CSI-2 Connector
# create_bd_port -dir O dphy_hs_clock_clk_p
# create_bd_port -dir O dphy_clk_lp_n
# create_bd_port -dir O dphy_clk_lp_p
# create_bd_port -dir O -from 1 -to 0 dphy_data_lp_n
# create_bd_port -dir O -from 1 -to 0 dphy_data_lp_p
# create_bd_port -dir O dphy_hs_clock_clk_n
# create_bd_port -dir O dphy_hs_clock_clk_p
# create_bd_port -dir O -from 1 -to 0 dphy_data_hs_n
# create_bd_port -dir O -from 1 -to 0 dphy_data_hs_p
# create_bd_port -dir O cam_clk
# create_bd_port -dir IO cam_gpio
# create_bd_port -dir O cam_scl
# create_bd_port -dir IO cam_sda

# ## Unloaded Crypto Chip SWI (for future use)
# create_bd_port -dir IO crypto_sda

# ## Unconnected Pins (Zybo Z7-20 only)
# create_bd_port -dir O netic19_t9
# create_bd_port -dir O netic19_u10
# create_bd_port -dir O netic19_u5
# create_bd_port -dir O netic19_u8
# create_bd_port -dir O netic19_u9
# create_bd_port -dir O netic19_v10
# create_bd_port -dir O netic19_v11
# create_bd_port -dir O netic19_v5
# create_bd_port -dir O netic19_w10
# create_bd_port -dir O netic19_w11
# create_bd_port -dir O netic19_w9
# create_bd_port -dir O netic19_y9
