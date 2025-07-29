import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, ReadWrite
import random
from shim_spi_cfg_sync_base import shim_spi_cfg_sync_base

async def setup_testbench(dut, clk_period=4, time_unit='ns'):
    tb = shim_spi_cfg_sync_base(dut, clk_period, time_unit)
    return tb

@cocotb.test(skip=True)
async def test_reset(dut):
    tb = await setup_testbench(dut)
    tb.dut._log.info("STARTING TEST: test_reset")

    # First have the DUT at a known state
    await tb.reset()
    
    # Then start the monitor and scoreboard tasks
    monitor_and_scoreboard_task = cocotb.start_soon(tb.monitor_and_scoreboard())

    # Then apply the actual reset
    await tb.reset()

    # Give time to coroutines to finish and kill their tasks
    await RisingEdge(dut.spi_clk)
    await RisingEdge(dut.spi_clk)
    monitor_and_scoreboard_task.kill()


@cocotb.test(skip=True)
async def test_spi_cfg_sync(dut):
    tb = await setup_testbench(dut)
    tb.dut._log.info("STARTING TEST: test_spi_cfg_sync")

    # First have the DUT at a known state
    await tb.reset()

    # Then start the monitor and scoreboard tasks
    monitor_and_scoreboard_task = cocotb.start_soon(tb.monitor_and_scoreboard())

    # Then apply the actual reset
    await tb.reset()

    # Drive some random inputs to the DUT
    await tb.one_time_driver()

    # Wait for the test to complete
    await monitor_and_scoreboard_task

    # Give time to coroutines to finish
    await RisingEdge(dut.spi_clk)
    await RisingEdge(dut.spi_clk)
    monitor_and_scoreboard_task.kill()

@cocotb.test(skip=True)
async def test_spi_cfg_sync_with_reset(dut):
    tb = await setup_testbench(dut)
    tb.dut._log.info("STARTING TEST: test_spi_cfg_sync_with_reset")

    # First have the DUT at a known state
    await tb.reset()

    # Then start the monitor and scoreboard tasks
    monitor_and_scoreboard_task = cocotb.start_soon(tb.monitor_and_scoreboard())

    # Then apply the actual reset
    await tb.reset()

    # Drive some random inputs to the DUT
    await tb.one_time_driver()

    # Reset the DUT
    await tb.reset()

    # Drive some random inputs to the DUT
    await tb.one_time_driver()

    # Wait for the test to complete
    await monitor_and_scoreboard_task

    # Give time to coroutines to finish
    await RisingEdge(dut.spi_clk)
    await RisingEdge(dut.spi_clk)
    monitor_and_scoreboard_task.kill()


@cocotb.test()
async def synchronizer_stability_test(dut):
    tb = await setup_testbench(dut)
    tb.dut._log.info("STARTING TEST: synchronizer_stability_test")

    # Reset the DUT
    await tb.reset()

    await RisingEdge(dut.spi_clk)
    dut.spi_en.value = 1
    await RisingEdge(dut.spi_clk)
    dut.spi_en.value = 0
    await RisingEdge(dut.spi_clk)
    dut.spi_en.value = 1
    await RisingEdge(dut.spi_clk)
    await ReadOnly()

    for _ in range(4):
        await RisingEdge(dut.spi_clk)