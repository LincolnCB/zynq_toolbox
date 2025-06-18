import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, ReadWrite

class latch_high_base:

    def __init__(self, dut, clk_period=4, time_unit="ns"):
        self.dut = dut

        # Get parameters from the DUT
        self.WIDTH = int(self.dut.WIDTH.value)
        self.MAX_VALUE = (2**self.WIDTH) - 1

        self.dut._log.info(f"LATCH PARAMETERS: WIDTH={self.WIDTH}")

        # Start the clock
        cocotb.start_soon(Clock(self.dut.clk, clk_period, units=time_unit).start())

        # Initialize input signals
        self.dut.din.value = 0

    async def reset(self):
        """
        Resets the DUT for 2 clk cycles.
        """
        await RisingEdge(self.dut.clk)
        self.dut._log.info("STARTING RESET")
        self.dut.resetn.value = 0 
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.resetn.value = 1
        self.dut._log.info("RESET COMPLETE")