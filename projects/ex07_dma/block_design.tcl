# No external FPGA ports are used in this project.
#
# Example 07: DDR-backed FIFO buffers via AXI MCDMA.
#
# This replaces the earlier single-channel axi_dma loopback scaffold with a
# parameterized AXI MCDMA engine. It stands up:
#   - one MCDMA with `num_ch` MM2S (PS->PL) and `num_ch` S2MM (PL->PS) channels,
#     each with its own descriptor queue and interrupt,
#   - GP0 as the control path to the MCDMA register window (S_AXI_LITE),
#   - HP0 as the 64-bit memory path to DDR, shared by the MCDMA data masters and
#     its scatter-gather descriptor-fetch master,
#   - a selectable AXI4-Stream datapath (see `datapath` below): either a single
#     TDEST-routed loopback (default, for validating the MCDMA path first) or the
#     fuller per-channel-FIFO structure with a TDEST demux/mux.
#
# The two datapaths are mutually exclusive branches of one `if`, so the default
# build exercises only the simple loopback -- the per-channel branch is inert
# (parsed but not run) until `datapath` is flipped, which keeps the first
# bring-up checkable on its own.
#
# VALIDATION NOTES:
#   - CONFIRMED on hardware (datapath = loopback, 2+2, byte-exact round trip):
#     interrupt pins mm2s_ch{i}_introut / s2mm_ch{i}_introut (1-indexed); single
#     datapath clock s_axi_aclk (MM2S/S2MM/SG) plus s_axi_lite_aclk; dedicated
#     M_AXI_SG master; AXIS stream-width params are read-only (derived); the 64K
#     control window (pl-reg reports size 0x10000); and MM2S drives TDEST from the
#     channel index so S2MM routes each channel back to itself.
#   - STILL TO CONFIRM:
#   - buffer-length register width (set to 23 bits = 8 MB/descriptor; not yet
#     stress-tested -- the loopback uses 2 KB transfers),
#   - axis_switch:1.1 TDEST routing config (ROUTING_MODE, per-MI
#     BASETDEST/HIGHTDEST) used in the not-yet-built per-channel branch.

############# Parameters #############

# Channels per direction. 2+2 is the first bring-up; bump to 4+4 to measure LUT
# scaling for the parent project. Everything below loops over this.
set num_ch 2

# AXI4-Stream datapath topology between MM2S and S2MM:
#   "loopback"    - single TDEST-routed elastic FIFO. Default: gets the MCDMA,
#                   HP0 path, and per-channel interrupts validated first with the
#                   least PL logic. Each MM2S channel returns to its S2MM channel
#                   because TDEST is preserved through the FIFO.
#   "per_channel" - TDEST demux -> per-channel "DAC FIFO" -> (traffic-gen
#                   insertion point) -> per-channel "ADC FIFO" -> TDEST mux. This
#                   is the structure the parent project needs (independent
#                   per-channel FIFOs and rates). Needs the axis_switch routing
#                   config validated, and the rate-gen custom core to exist before
#                   its commented insertion point is enabled.
set datapath loopback

############# General setup #############

## Instantiate the processing system
# - Unused AXI ACP port disabled
# - HP0 enabled: the MCDMA's 64-bit path to DDR (payload + SG descriptor fetches)
# - GP0 (default) carries the MCDMA S_AXI_LITE control window
init_ps ps {
  PCW_USE_S_AXI_ACP 0
  PCW_USE_S_AXI_HP0 1
} {
  M_AXI_GP0_ACLK ps/FCLK_CLK0
  S_AXI_HP0_ACLK ps/FCLK_CLK0
}

## PS reset core
cell xilinx.com:ip:proc_sys_reset:5.0 ps_rst {} {
  ext_reset_in ps/FCLK_RESET0_N
  slowest_sync_clk ps/FCLK_CLK0
}

### AXI SmartConnect cores
# PS -> MCDMA control (GP0 to S_AXI_LITE)
cell xilinx.com:ip:smartconnect:1.0 axi_ctrl_intercon {
  NUM_SI 1
  NUM_MI 1
} {
  aclk ps/FCLK_CLK0
  aresetn ps_rst/peripheral_aresetn
  S00_AXI /ps/M_AXI_GP0
}
# MCDMA memory masters -> DDR. Three subordinate ports aggregate onto HP0:
# M_AXI_MM2S (payload out), M_AXI_S2MM (payload in), M_AXI_SG (descriptor fetch).
cell xilinx.com:ip:smartconnect:1.0 axi_mem_intercon {
  NUM_SI 3
  NUM_MI 1
} {
  aclk ps/FCLK_CLK0
  aresetn ps_rst/peripheral_aresetn
  M00_AXI ps/S_AXI_HP0
}

############# AXI MCDMA #############

## One MCDMA with num_ch channels per direction.
# - Memory-map data width 64 (matches HP0); do not run HP0 in 32-bit mode.
# - The AXIS stream data-width is NOT a settable knob: c_m_axis_mm2s_tdata_width /
#   c_s_axis_s2mm_tdata_width are read-only (derived), so they are left at the IP
#   default. Fine for this loopback (MM2S loops straight into S2MM). Matching the
#   parent project's 32-bit FIFOs later is a memory-width/DRE question -- VALIDATE.
# - Clocking: MCDMA has a single datapath clock `s_axi_aclk` (shared by MM2S,
#   S2MM and SG) plus the AXI-Lite clock `s_axi_lite_aclk`. There are no per-master
#   m_axi_*_aclk pins (confirmed against AMD's Kria MCDMA reference designs).
# - Scatter-gather enabled (mandatory on MCDMA); descriptor rings live in DDR and
#   are fetched over M_AXI_SG.
# - Buffer-length register widened to 23 bits so a contiguous multi-MB transfer
#   is a single descriptor instead of a 16 KB-capped chain.
# - VLNV <xilinx.com:ip:axi_mcdma:1.1> is not supported for zynq-7020
#   The latest supported version for this part is: <1.2>
cell xilinx.com:ip:axi_mcdma:1.2 mcdma {
  c_num_mm2s_channels $num_ch
  c_num_s2mm_channels $num_ch
  c_include_mm2s 1
  c_include_s2mm 1
  c_include_sg 1
  c_sg_length_width 23
  c_addr_width 32
  c_m_axi_mm2s_data_width 64
  c_m_axi_s2mm_data_width 64
} {
  s_axi_lite_aclk ps/FCLK_CLK0
  s_axi_aclk ps/FCLK_CLK0
  axi_resetn ps_rst/peripheral_aresetn
  S_AXI_LITE axi_ctrl_intercon/M00_AXI
  M_AXI_MM2S axi_mem_intercon/S00_AXI
  M_AXI_S2MM axi_mem_intercon/S01_AXI
  M_AXI_SG   axi_mem_intercon/S02_AXI
}

## Addresses
# MCDMA control window on GP0
addr 0x40400000 64K mcdma/S_AXI_LITE ps/M_AXI_GP0
# DDR windows seen by each MCDMA memory master over HP0 (full 1 GB LPDDR2)
addr 0x00000000 1G ps/S_AXI_HP0 mcdma/M_AXI_MM2S
addr 0x00000000 1G ps/S_AXI_HP0 mcdma/M_AXI_S2MM
addr 0x00000000 1G ps/S_AXI_HP0 mcdma/M_AXI_SG

############# Interrupts #############

# Per-channel interrupts: num_ch MM2S + num_ch S2MM, concatenated into IRQ_F2P.
# IRQ_F2P[0..7] map to GIC IDs 61-68 (device tree <0 29 4> .. <0 36 4>); with
# 2+2 channels only the low 4 lines are used. MM2S channels take the low ports,
# S2MM channels the high ports.
cell xilinx.com:ip:xlconcat:2.1 intr_concat {
  NUM_PORTS [expr {2 * $num_ch}]
} {
  dout ps/IRQ_F2P
}
for {set i 0} {$i < $num_ch} {incr i} {
  set ch [expr {$i + 1}]
  wire mcdma/mm2s_ch${ch}_introut intr_concat/In${i}
}
for {set i 0} {$i < $num_ch} {incr i} {
  set ch [expr {$i + 1}]
  set port [expr {$num_ch + $i}]
  wire mcdma/s2mm_ch${ch}_introut intr_concat/In${port}
}

############# AXI4-Stream datapath #############

if {$datapath eq "loopback"} {

  ## Simple loopback (default): one elastic FIFO, TDEST preserved end to end.
  # MCDMA MM2S emits a single stream multiplexed by TDEST (TDEST = channel
  # index); S2MM consumes a single stream routed by TDEST. Looping MM2S straight
  # back into S2MM returns each channel's data to the matching S2MM channel
  # automatically, giving a working multi-channel round trip with no per-channel
  # wiring. TLAST and TDEST are carried through the FIFO.
  cell xilinx.com:ip:axis_data_fifo:2.0 axis_loopback {
    TDATA_NUM_BYTES 4
    HAS_TLAST 1
    TDEST_WIDTH 8
    FIFO_DEPTH 512
  } {
    S_AXIS mcdma/M_AXIS_MM2S
    M_AXIS mcdma/S_AXIS_S2MM
    s_axis_aresetn ps_rst/peripheral_aresetn
    s_axis_aclk ps/FCLK_CLK0
  }

} elseif {$datapath eq "per_channel"} {

  ## Fuller structure: per-channel FIFOs with a TDEST demux/mux.
  # This mirrors rev_d_shim, where each board has its own DAC and ADC FIFO and a
  # SPI core in between. Here the DAC FIFO buffers MM2S data, the ADC FIFO buffers
  # PL-produced data, and (eventually) a programmable-rate traffic generator sits
  # between them playing the SPI core's role.

  ## TDEST demux: MM2S single stream -> num_ch per-channel streams.
  # ROUTING_MODE for TDEST-based routing; each MI accepts one TDEST value. The
  # exact CONFIG names/values are axis_switch-version-specific -- validate.
  cell xilinx.com:ip:axis_switch:1.1 mm2s_demux {
    NUM_SI 1
    NUM_MI $num_ch
    ROUTING_MODE 0
    TDEST_WIDTH 8
    DECODER_REG 1
  } {
    S00_AXIS mcdma/M_AXIS_MM2S
    aclk ps/FCLK_CLK0
    aresetn ps_rst/peripheral_aresetn
  }

  ## TDEST mux: num_ch per-channel streams -> S2MM single stream.
  # 1 MI just arbitrates; TDEST passes through so S2MM still routes by channel.
  cell xilinx.com:ip:axis_switch:1.1 s2mm_mux {
    NUM_SI $num_ch
    NUM_MI 1
    ARB_ON_TLAST 1
    TDEST_WIDTH 8
  } {
    M00_AXIS mcdma/S_AXIS_S2MM
    aclk ps/FCLK_CLK0
    aresetn ps_rst/peripheral_aresetn
  }

  ## Per-channel routing + FIFOs
  for {set i 0} {$i < $num_ch} {incr i} {
    set mi [format M%02d $i]
    set si [format S%02d $i]

    # Route demux MI i to TDEST == i (property names to validate for this IP rev).
    set_property -dict [list \
      CONFIG.${mi}_AXIS_BASETDEST $i \
      CONFIG.${mi}_AXIS_HIGHTDEST $i] [get_bd_cells mm2s_demux]

    # "DAC FIFO": buffers MM2S data for channel i (drained by the SPI core in
    # rev_d_shim; by the traffic gen / loopback here).
    cell xilinx.com:ip:axis_data_fifo:2.0 dac_fifo_${i} {
      TDATA_NUM_BYTES 4
      HAS_TLAST 1
      TDEST_WIDTH 8
      FIFO_DEPTH 512
    } {
      S_AXIS mm2s_demux/${mi}_AXIS
      s_axis_aclk ps/FCLK_CLK0
      s_axis_aresetn ps_rst/peripheral_aresetn
    }

    # "ADC FIFO": buffers PL-produced data for channel i (filled by the SPI core
    # in rev_d_shim; by the traffic gen / loopback here).
    cell xilinx.com:ip:axis_data_fifo:2.0 adc_fifo_${i} {
      TDATA_NUM_BYTES 4
      HAS_TLAST 1
      TDEST_WIDTH 8
      FIFO_DEPTH 512
    } {
      M_AXIS s2mm_mux/${si}_AXIS
      s_axis_aclk ps/FCLK_CLK0
      s_axis_aresetn ps_rst/peripheral_aresetn
    }

    # ---- Traffic generator / checker insertion point (custom core, TODO) ----
    # Until the rate-gen core exists, loop the DAC FIFO straight into the ADC
    # FIFO so the per-channel path is still exercisable (TDEST == i is preserved,
    # so S2MM routes it back to channel i):
    wire dac_fifo_${i}/M_AXIS adc_fifo_${i}/S_AXIS
    #
    # When the rate-gen core lands, delete the wire above and instead drop it in
    # between the two FIFOs, e.g.:
    #   cell <vendor>:user:axis_rate_gen rate_gen_${i} {
    #     ...rate/pause params...
    #   } {
    #     s_axis dac_fifo_${i}/M_AXIS
    #     m_axis adc_fifo_${i}/S_AXIS
    #     aclk ps/FCLK_CLK0
    #     aresetn ps_rst/peripheral_aresetn
    #   }
  }

} else {
  error "Unknown datapath '$datapath' (expected 'loopback' or 'per_channel')"
}
