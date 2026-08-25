import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly


class axi_rate_gen_base:
    """Test harness for the axi_rate_gen AXI4-Stream rate limiter.

    Drives the slave (DAC-side) stream and consumes the master (ADC-side)
    stream, hand-rolling the AXI4-Stream handshake the way the other cores in
    this repo do (no cocotbext dependency).
    """

    # cfg bit fields (mirror axi_rate_gen.v)
    CFG_PAUSE_BIT = 16

    def __init__(self, dut, clk_period=10, time_unit="ns"):
        self.dut = dut

        self.DATA_WIDTH = int(self.dut.DATA_WIDTH.value)
        self.DEST_WIDTH = int(self.dut.DEST_WIDTH.value)
        self.RATE_WIDTH = int(self.dut.RATE_WIDTH.value)
        self.DATA_MASK = (1 << self.DATA_WIDTH) - 1
        self.DEST_MASK = (1 << self.DEST_WIDTH) - 1
        self.RATE_MASK = (1 << self.RATE_WIDTH) - 1

        cocotb.start_soon(Clock(self.dut.clk if hasattr(self.dut, "clk") else self.dut.aclk,
                                clk_period, units=time_unit).start())

        # Initialize inputs
        self.dut.cfg.value = 0
        self.dut.s_axis_tdata.value = 0
        self.dut.s_axis_tdest.value = 0
        self.dut.s_axis_tlast.value = 0
        self.dut.s_axis_tvalid.value = 0
        self.dut.m_axis_tready.value = 0

    def set_cfg(self, rate_div=0, pause=0):
        cfg = (rate_div & self.RATE_MASK) | ((pause & 1) << self.CFG_PAUSE_BIT)
        self.dut.cfg.value = cfg

    async def reset(self):
        await RisingEdge(self.dut.aclk)
        self.dut.aresetn.value = 0
        self.dut.s_axis_tvalid.value = 0
        self.dut.m_axis_tready.value = 0
        await RisingEdge(self.dut.aclk)
        await RisingEdge(self.dut.aclk)
        self.dut.aresetn.value = 1
        await RisingEdge(self.dut.aclk)

    async def send_and_receive(self, words, dest=0, ready=True, timeout_cycles=100000):
        """Push `words` into the slave stream while consuming the master stream.

        Both sides run concurrently. Returns the list of (data, tlast) beats
        seen on the master side. `ready` fixes m_axis_tready high (or low, to
        exercise backpressure -- then this returns whatever was captured).
        """
        received = []
        n = len(words)

        async def driver():
            idx = 0
            while idx < n:
                self.dut.s_axis_tdata.value = words[idx] & self.DATA_MASK
                self.dut.s_axis_tdest.value = dest & self.DEST_MASK
                self.dut.s_axis_tlast.value = 1 if idx == n - 1 else 0
                self.dut.s_axis_tvalid.value = 1
                await ReadOnly()
                fired = (self.dut.s_axis_tvalid.value == 1 and self.dut.s_axis_tready.value == 1)
                await RisingEdge(self.dut.aclk)
                if fired:
                    idx += 1
            self.dut.s_axis_tvalid.value = 0
            self.dut.s_axis_tlast.value = 0

        async def monitor():
            cycles = 0
            while len(received) < n and cycles < timeout_cycles:
                self.dut.m_axis_tready.value = 1 if ready else 0
                await ReadOnly()
                if self.dut.m_axis_tvalid.value == 1 and self.dut.m_axis_tready.value == 1:
                    received.append((int(self.dut.m_axis_tdata.value),
                                     int(self.dut.m_axis_tlast.value)))
                await RisingEdge(self.dut.aclk)
                cycles += 1

        drv = cocotb.start_soon(driver())
        mon = cocotb.start_soon(monitor())
        await mon
        if ready:
            await drv
        self.dut.m_axis_tready.value = 0
        return received
