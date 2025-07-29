import cocotb
from cocotb.triggers import RisingEdge, ReadOnly, Timer
import random
from axi_fifo_bridge_base import axi_fifo_bridge_base

async def setup_testbench(dut, clk_period=4, time_unit='ns'):
    tb = axi_fifo_bridge_base(dut, clk_period, time_unit)
    return tb

@cocotb.test()
async def test_single_write_and_read(dut):
    tb = await setup_testbench(dut)
    tb.dut._log.info("STARTING TEST: test_single_write_and_read")

    # First have the DUT at a known state
    await tb.reset()

    # Start the FIFO model
    model_fifo_task = cocotb.start_soon(tb.sw_fwft_fifo_model())

    # Actual reset
    await tb.reset()

    # Master sends a single write transaction
    test_data = random.randint(0, 2**tb.AXI_DATA_WIDTH - 1)
    await tb.axi4l_single_write_channel(test_data)

    # Master sends a single read transaction
    await tb.axi4l_single_read_channel()

    await RisingEdge(dut.aclk)
    await RisingEdge(dut.aclk)
    model_fifo_task.kill()
