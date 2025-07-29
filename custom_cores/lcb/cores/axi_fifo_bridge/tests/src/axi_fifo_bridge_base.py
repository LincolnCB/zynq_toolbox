import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, ReadWrite
import random
from collections import deque

class axi_fifo_bridge_base:

    def __init__(self, dut, clk_period=4, time_unit='ns'):
        
        self.dut = dut
        self.clk_period = clk_period
        self.time_unit = time_unit

        # Get Parameters from the DUT
        self.AXI_ADDR_WIDTH = int(self.dut.AXI_ADDR_WIDTH.value)
        self.AXI_DATA_WIDTH = int(self.dut.AXI_DATA_WIDTH.value)
        self.AXI_DATA_BYTES = self.AXI_DATA_WIDTH // 8
        self.ENABLE_WRITE   = int(self.dut.ENABLE_WRITE.value)
        self.ENABLE_READ    = int(self.dut.ENABLE_READ.value)

        self.dut._log.info("INITIALIZING axi_fifo_bridge_base with PARAMETERS:")
        self.dut._log.info(f"AXI_ADDR_WIDTH: {self.AXI_ADDR_WIDTH}")
        self.dut._log.info(f"AXI_DATA_WIDTH: {self.AXI_DATA_WIDTH}")
        self.dut._log.info(f"ENABLE_WRITE: {self.ENABLE_WRITE}")
        self.dut._log.info(f"ENABLE_READ: {self.ENABLE_READ}")

        # Initialize the clock
        cocotb.start_soon(Clock(dut.aclk, clk_period, time_unit).start(start_high=False))

        # Initialize AXI4-Lite Signals
        self.dut.s_axi_awaddr.value = 0 
        self.dut.s_axi_awvalid.value = 0
        self.dut.s_axi_wdata.value = 0
        self.dut.s_axi_wstrb.value = 0
        self.dut.s_axi_wvalid.value = 0
        self.dut.s_axi_bready.value = 0
        self.dut.s_axi_araddr.value = 0
        self.dut.s_axi_arvalid.value = 0
        self.dut.s_axi_rready.value = 0

        # FIFO Model
        self.fifo_model = deque()
        self.FIFO_DEPTH = 16 # Can be changed
        self.dut._log.info(f"MODEL FIFO_DEPTH set to {self.FIFO_DEPTH}") 

        # Initialize FIFO signals
        self.dut.fifo_full.value = 0
        self.dut.fifo_empty.value = 1
        self.dut.fifo_rd_data.value = 0

    async def reset(self):
        await RisingEdge(self.dut.aclk)
        self.dut.aresetn.value = 0
        self.dut._log.info("STARTING RESET")
        self.fifo_model.clear()
        await RisingEdge(self.dut.aclk)
        await RisingEdge(self.dut.aclk)
        self.dut.aresetn.value = 1
        self.dut._log.info("RESET COMPLETE")

    async def sw_fwft_fifo_model(self):
        """Model the FIFO behavior."""
        while True:
            await RisingEdge(self.dut.aclk)
            await ReadWrite() # Wait for initial combinational logic to settle 

            # FIFO writes
            if self.dut.fifo_wr_en.value == 1:
                if len(self.fifo_model) < self.FIFO_DEPTH:
                    data = int(self.dut.fifo_wr_data.value)
                    self.fifo_model.append(data)
                    self.dut._log.info(f"Model FIFO Write: 0x{data:08x} (depth: {len(self.fifo_model)})")
                else:
                    self.dut._log.warning("Model FIFO Write attempted but FIFO is full.")

            # FIFO reads
            if self.dut.fifo_rd_en.value == 1:
                if len(self.fifo_model) > 0:
                    # Pop the data that was already "falling through"
                    popped_data = self.fifo_model.popleft()
                    self.dut._log.info(f"Model FIFO Read Acknowledged. Popped: 0x{popped_data:08x} (new depth: {len(self.fifo_model)})")
                else:
                    self.dut._log.warning("FIFO Read Enable asserted when empty!")

            if len(self.fifo_model) > 0:
                # "Peek" at the first item without removing it
                current_output_data = self.fifo_model[0]
                
                # FWFT behavior
                self.dut.fifo_rd_data.value = current_output_data
            else:
                # When the FIFO becomes empty, the output data is no longer valid.
                self.dut.fifo_rd_data.value = 0

            # Update FIFO status signals
            self.dut.fifo_full.value = 1 if len(self.fifo_model) >= self.FIFO_DEPTH else 0
            self.dut.fifo_empty.value = 1 if len(self.fifo_model) == 0 else 0

    async def axi4l_single_write_channel(self, data):

        await RisingEdge(self.dut.aclk)
        # Master sends a valid write address and data
        self.dut.s_axi_awvalid.value = 1
        self.dut.s_axi_wdata.value = data
        self.dut.s_axi_wvalid.value = 1

        await RisingEdge(self.dut.aclk)
        # Master deasserts the write address and data valid signals
        self.dut.s_axi_awvalid.value = 0
        self.dut.s_axi_wvalid.value = 0

        # Master sends write response ready
        self.dut.s_axi_bready.value = 1

        await RisingEdge(self.dut.aclk)
        # Master deasserts the write response ready signal
        self.dut.s_axi_bready.value = 0

    async def axi4l_single_read_channel(self):

        await RisingEdge(self.dut.aclk)
        # Master sends a valid read address 
        self.dut.s_axi_arvalid.value = 1

        await RisingEdge(self.dut.aclk)
        # Master deasserts the read address valid signal
        self.dut.s_axi_arvalid.value = 0

        # Master sends read data ready
        self.dut.s_axi_rready.value = 1

        await RisingEdge(self.dut.aclk)
        # Master deasserts the read data ready signal
        self.dut.s_axi_rready.value = 0

