import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, ReadWrite, Combine
import random
from sync_coherent_base import sync_coherent_base

async def setup_testbench(dut, in_clk_period=4, out_clk_period=4, time_unit="ns"):
    tb = sync_coherent_base(dut, in_clk_period, out_clk_period, time_unit)
    return tb


@cocotb.test()
async def test_prev_din_after_reset(dut):
    pass

@cocotb.test()
async def test_random(dut):
    # Random seed
    seed = 1234
    random.seed(seed)
    dut._log.info(f"Random seed set to: {seed}")

    # Test Iteration
    for i in range(10):
        in_clk_period = random.randint(4, 20)
        out_clk_period = random.randint(4, 20)

        tb = await setup_testbench(dut, in_clk_period, out_clk_period)
        tb.dut._log.info(f"STARTING TEST: Random Tests Iteration: {i+1}")
        await tb.start_clocks()

        # Perform reset
        in_side_reset_task = cocotb.start_soon(tb.in_side_reset())
        out_side_reset_task = cocotb.start_soon(tb.out_side_reset())

        await in_side_reset_task
        await out_side_reset_task

        # Start coroutines
        din_driver_and_monitor_task = cocotb.start_soon(tb.din_driver_and_monitor(cycles=10))
        dout_scoreboard_task = cocotb.start_soon(tb.dout_scoreboard(cycles=10))

        # Wait for coroutines to complete
        await din_driver_and_monitor_task
        await dout_scoreboard_task

        # Ensure we don't collide with the new iteration
        await RisingEdge(dut.in_clk)
        await RisingEdge(dut.out_clk)
        await RisingEdge(dut.in_clk)
        await RisingEdge(dut.out_clk)
        await tb.kill_clocks()
        din_driver_and_monitor_task.kill()
        dout_scoreboard_task.kill()


