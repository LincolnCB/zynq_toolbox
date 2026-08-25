# No external FPGA ports are used in this project.
#
# Example 05: DDR-backed FIFO buffers via AXI MCDMA.
#
# Stands up:
#   - one MCDMA with `num_ch` MM2S (PS->PL) and `num_ch` S2MM (PL->PS) channels,
#     each with its own descriptor queue and interrupt,
#   - GP0 as the control path to the MCDMA register window (S_AXI_LITE),
#   - HP0 as the 64-bit memory path to DDR, shared by the MCDMA data masters and
#     its scatter-gather descriptor-fetch master,
#   - a per-channel AXI4-Stream datapath: a TDEST demux fans MM2S out to num_ch
#     FIFOs, and a packet-atomic TDEST mux merges them back into S2MM.
#   - a per-channel axi_rate_gen pacer between each DAC and ADC FIFO (the SPI
#     core's role in rev_d_shim), controlled by a shared cfg/sts register pair
#     (rate_cfg / rate_sts on GP0, reachable non-root via pl-reg).
#   - a per-channel register-driven FIFO reset (buf_reset on GP0, non-root via
#     pl-reg): bit i clears channel i's DAC and ADC FIFO. This is the coordinated
#     halt/clear/reset path -- software halts the MCDMA, asserts buf_reset to flush
#     stranded data, then reinitializes the descriptor rings (see software/halt-reset).
#   - all 2*num_ch MCDMA completion/error interrupts OR-reduced onto a single
#     IRQ_F2P line, exposed to userspace non-root by the pl-irq module (see software/dma-irq).
#
# Design notes:
#   - AXIS stream width is read-only (derived) on the MCDMA; it is 32-bit here.
#     Memory-map width is 64 to match HP0 (do not run HP0 in 32-bit mode).
#   - Interrupt pins mm2s_ch{i}_introut / s2mm_ch{i}_introut are 1-indexed.
#   - Single datapath clock s_axi_aclk (MM2S/S2MM/SG) plus s_axi_lite_aclk; the
#     MCDMA has no per-master m_axi_*_aclk pins.
#   - MM2S drives TDEST from the channel index, so S2MM routes each channel back
#     to itself. axis_switch TDEST windows are bitString params: pass 0x hex via
#     [format ...], and a single-MI window must span [0, num_ch-1] or every
#     channel but 0 is dropped.
#   - The s2mm_mux (axis_switch, num_ch SI -> 1 MI) arbitrates packet-atomically:
#     HAS_TLAST must be set explicitly so ARB_ON_TLAST takes, else the arbiter
#     re-arbitrates per beat and channels 1..n starve.
#   - Buffer-length register is 23 bits (8 MB/descriptor).

############# Parameters #############

# Channels per direction; everything below loops over this. Bump to measure LUT
# scaling (MCDMA vs. separate axi_dma) for the parent project.
set num_ch 8

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
# PS -> control windows on GP0: the MCDMA S_AXI_LITE, the rate-gen cfg/sts
# register windows, and the FIFO buf_reset register (M00/M01/M02/M03 below).
cell xilinx.com:ip:smartconnect:1.0 axi_ctrl_intercon {
  NUM_SI 1
  NUM_MI 4
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
# - The AXIS stream data-width is read-only (derived): c_m_axis_mm2s_tdata_width
#   / c_s_axis_s2mm_tdata_width are not settable knobs, so they are left at the
#   IP default (32-bit here).
# - Clocking: a single datapath clock `s_axi_aclk` (shared by MM2S, S2MM and SG)
#   plus the AXI-Lite clock `s_axi_lite_aclk`. There are no per-master
#   m_axi_*_aclk pins.
# - Scatter-gather enabled (mandatory on MCDMA); descriptor rings live in DDR and
#   are fetched over M_AXI_SG.
# - Buffer-length register set to 23 bits so a contiguous multi-MB transfer
#   is a single descriptor instead of a 16 KB-capped chain.
# - Version 1.2: axi_mcdma:1.1 is not supported on zynq-7020.
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

############# Rate-gen control registers #############

# One shared cfg/sts register pair backs the per-channel axi_rate_gen cores:
# 32 bits per channel, packed into a single wide window each. Reachable non-root
# via pl-reg as /dev/rate_cfg and /dev/rate_sts (its match table already lists
# the axi-cfg-register / axi-sts-register compatibles -- see ex03). The per-
# channel slices are wired up inside the datapath loop below.

# Writable config: channel i's control word is cfg_data[32*i +: 32].
cell pavel-demin:user:axi_cfg_register rate_cfg {
  CFG_DATA_WIDTH [expr {32 * $num_ch}]
  AXI_ADDR_WIDTH 16
} {
  aclk ps/FCLK_CLK0
  aresetn ps_rst/peripheral_aresetn
  S_AXI axi_ctrl_intercon/M01_AXI
}
addr 0x40410000 64K rate_cfg/S_AXI ps/M_AXI_GP0

# Read-only status: channel i's status word is sts_data[32*i +: 32], assembled
# from the per-channel rate_gen sts outputs by this concat. Each input port is
# widened to 32 bits up front so dout is 32*num_ch wide before rate_sts binds it.
cell xilinx.com:ip:xlconcat:2.1 rate_sts_concat {
  NUM_PORTS $num_ch
} {}
for {set i 0} {$i < $num_ch} {incr i} {
  set_property CONFIG.IN${i}_WIDTH 32 [get_bd_cells rate_sts_concat]
}
cell pavel-demin:user:axi_sts_register rate_sts {
  STS_DATA_WIDTH [expr {32 * $num_ch}]
  AXI_ADDR_WIDTH 16
} {
  aclk ps/FCLK_CLK0
  aresetn ps_rst/peripheral_aresetn
  sts_data rate_sts_concat/dout
  S_AXI axi_ctrl_intercon/M02_AXI
}
addr 0x40420000 64K rate_sts/S_AXI ps/M_AXI_GP0

############# FIFO buffer-reset register #############

# One shared cfg register drives the per-channel datapath FIFO reset: bit i
# clears channel i's DAC and ADC FIFO (num_ch bits used, one write access).
# Reachable non-root via pl-reg as /dev/buf_reset (same axi-cfg-register
# compatible the match table already lists). The per-channel reset logic is
# wired up in the datapath loop below. This backs the coordinated halt -> clear
# -> reinit path: software halts the MCDMA first, then pulses buf_reset to flush
# data stranded in a FIFO, mirroring rev_d_shim's axi_sys_ctrl data_buf_reset
# (which must never be pulsed while an MCDMA channel is mid-transfer -- see the
# project README).
#
# CFG_DATA_WIDTH must be a multiple of AXI_DATA_WIDTH (32): the core sizes its
# register file as CFG_SIZE = CFG_DATA_WIDTH/32, so any width below 32 rounds to
# zero storage and cfg_data ties off to 0 (the register silently does nothing).
# One 32-bit word holds up to 32 channels; round num_ch up to a 32-bit multiple.
set buf_reset_width [expr {(($num_ch + 31) / 32) * 32}]
cell pavel-demin:user:axi_cfg_register buf_reset {
  CFG_DATA_WIDTH $buf_reset_width
  AXI_ADDR_WIDTH 16
} {
  aclk ps/FCLK_CLK0
  aresetn ps_rst/peripheral_aresetn
  S_AXI axi_ctrl_intercon/M03_AXI
}
addr 0x40430000 64K buf_reset/S_AXI ps/M_AXI_GP0

############# Interrupts #############

# All 2*num_ch MCDMA channel interrupts (num_ch MM2S completion/error + num_ch
# S2MM completion/error) are concatenated and then OR-reduced into a single
# PL->PS interrupt line on IRQ_F2P[0] (GIC ID 61, device tree <0 29 4>). The
# pl-irq module (see the device tree) binds it and exposes it to userspace as one
# non-root misc device /dev/mcdma_irq: software blocks on read()/poll() as a
# doorbell, then reads each channel's MCDMA status register to find which
# channel(s) completed or errored. This mirrors rev_d_shim, which folds all DMA
# events into hw_manager's single error-alert IRQ rather than dedicating one GIC
# line per channel.
cell xilinx.com:ip:xlconcat:2.1 intr_concat {
  NUM_PORTS [expr {2 * $num_ch}]
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
# OR-reduce the concatenated interrupt bus onto the single IRQ_F2P[0] line.
cell xilinx.com:ip:util_reduced_logic:2.0 intr_or {
  C_SIZE      [expr {2 * $num_ch}]
  C_OPERATION or
} {
  Op1 intr_concat/dout
  Res ps/IRQ_F2P
}

############# AXI4-Stream datapath #############

# Per-channel FIFOs with a TDEST demux/mux. This mirrors rev_d_shim, where each
# board has its own DAC and ADC FIFO and a SPI core in between. Here the DAC FIFO
# buffers MM2S data, the ADC FIFO buffers PL-produced data, and a programmable-
# rate pacer (axi_rate_gen, wired up in the loop below) sits between them playing
# the SPI core's role.

## TDEST demux: MM2S single stream -> num_ch per-channel streams.
# ROUTING_MODE 0 = TDEST-based routing; each MI accepts one TDEST value, set
# per-MI in the loop below.
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
# Stock axis_switch (ROUTING_MODE 0, num_ch SI -> 1 MI) doing a packet-atomic
# round-robin merge. HAS_TLAST is set explicitly so ARB_ON_TLAST takes -- it
# depends on TLAST being present, so leaving it to propagation makes the tool
# drop it and the arbiter re-arbitrates every beat (channels 1..n starve). With
# it set, the arbiter holds a granted SI to TLAST and packets never interleave;
# ARB_ON_MAX_XFERS 1024 is just a backstop above the 512-beat packet. The MI's
# TDEST decode window spans [0, num_ch-1] (0x hex, the IP's bitString format) or
# it drops every channel but 0; TDEST/TLAST pass through so MCDMA S2MM still
# demuxes each packet by TDEST.
cell xilinx.com:ip:axis_switch:1.1 s2mm_mux {
  NUM_SI $num_ch
  NUM_MI 1
  ROUTING_MODE 0
  ARB_ALGORITHM 0
  ARB_ON_TLAST 1
  ARB_ON_MAX_XFERS 1024
  HAS_TLAST 1
  HAS_ACLKEN 0
  TDATA_NUM_BYTES 4
  TDEST_WIDTH 8
  M00_AXIS_BASETDEST [format 0x%08X 0]
  M00_AXIS_HIGHTDEST [format 0x%08X [expr {$num_ch - 1}]]
} {
  M00_AXIS mcdma/S_AXIS_S2MM
  aclk ps/FCLK_CLK0
  aresetn ps_rst/peripheral_aresetn
}

## Per-channel routing + FIFOs
for {set i 0} {$i < $num_ch} {incr i} {
  set mi [format M%02d $i]
  set si [format S%02d $i]

  # Route demux MI i to TDEST == i. Pass 0x-prefixed hex: these bitString
  # params must not be bare integers, or the derived C_M_AXIS_*TDEST_ARRAY
  # modelparam rejects any value needing more than one bit.
  set_property -dict [list \
    CONFIG.${mi}_AXIS_BASETDEST [format 0x%08X $i] \
    CONFIG.${mi}_AXIS_HIGHTDEST [format 0x%08X $i]] [get_bd_cells mm2s_demux]

  # ---- Per-channel FIFO reset ----
  # buf_reset bit i, ANDed with the global peripheral reset, drives a per-channel
  # proc_sys_reset that clears both this channel's DAC and ADC FIFO. Mirrors the
  # rev_d_shim per-FIFO reset (slice -> NOT -> proc_sys_reset), so a mid-run FIFO
  # clear is a clean synchronized reset. The FIFOs reset on global peripheral
  # reset (buf_reset bit 0) or when software writes buf_reset bit i = 1.
  cell xilinx.com:ip:xlslice:1.0 buf_reset_slice_${i} {
    DIN_WIDTH $buf_reset_width
    DIN_FROM  $i
    DIN_TO    $i
  } {
    din buf_reset/cfg_data
  }
  cell xilinx.com:ip:util_vector_logic n_buf_reset_${i} {
    C_SIZE 1
    C_OPERATION not
  } {
    Op1 buf_reset_slice_${i}/dout
  }
  # FIFO reset asserted (active-low 0) on global reset OR this channel's buf_reset.
  cell xilinx.com:ip:util_vector_logic fifo_aresetn_${i} {
    C_SIZE 1
    C_OPERATION and
  } {
    Op1 n_buf_reset_${i}/Res
    Op2 ps_rst/peripheral_aresetn
  }
  cell xilinx.com:ip:proc_sys_reset:5.0 fifo_rst_${i} {} {
    ext_reset_in fifo_aresetn_${i}/Res
    slowest_sync_clk ps/FCLK_CLK0
  }

  # "DAC FIFO": buffers MM2S data for channel i (drained by the SPI core in
  # rev_d_shim; by the rate pacer below here).
  cell xilinx.com:ip:axis_data_fifo:2.0 dac_fifo_${i} {
    TDATA_NUM_BYTES 4
    HAS_TLAST 1
    TDEST_WIDTH 8
    FIFO_DEPTH 512
  } {
    S_AXIS mm2s_demux/${mi}_AXIS
    s_axis_aclk ps/FCLK_CLK0
    s_axis_aresetn fifo_rst_${i}/peripheral_aresetn
  }

  # "ADC FIFO": buffers PL-produced data for channel i (filled by the SPI core
  # in rev_d_shim; by the rate pacer below here).
  cell xilinx.com:ip:axis_data_fifo:2.0 adc_fifo_${i} {
    TDATA_NUM_BYTES 4
    HAS_TLAST 1
    TDEST_WIDTH 8
    FIFO_DEPTH 512
  } {
    M_AXIS s2mm_mux/${si}_AXIS
    s_axis_aclk ps/FCLK_CLK0
    s_axis_aresetn fifo_rst_${i}/peripheral_aresetn
  }

  # ---- Programmable-rate traffic pacer (custom core) ----
  # axi_rate_gen throttles the DAC->ADC stream for channel i to a programmed
  # rate (and can pause it), standing in for rev_d_shim's SPI core. TDEST == i
  # is preserved, so S2MM routes each channel back to itself.
  #
  # Its control word is slice [32*i +: 32] of rate_cfg; its status word feeds
  # port i of rate_sts_concat.
  cell xilinx.com:ip:xlslice:1.0 rate_cfg_slice_${i} {
    DIN_WIDTH [expr {32 * $num_ch}]
    DIN_FROM  [expr {32 * $i + 31}]
    DIN_TO    [expr {32 * $i}]
  } {
    din rate_cfg/cfg_data
  }
  cell base:user:axi_rate_gen rate_gen_${i} {
    DATA_WIDTH 32
    DEST_WIDTH 8
  } {
    cfg rate_cfg_slice_${i}/dout
    S_AXIS dac_fifo_${i}/M_AXIS
    M_AXIS adc_fifo_${i}/S_AXIS
    aclk ps/FCLK_CLK0
    aresetn ps_rst/peripheral_aresetn
  }
  wire rate_gen_${i}/sts rate_sts_concat/In${i}
}
