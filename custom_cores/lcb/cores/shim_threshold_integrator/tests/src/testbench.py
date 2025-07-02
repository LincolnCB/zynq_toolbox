import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, ReadWrite, Join
import random
from shim_threshold_integrator_base import shim_threshold_integrator_base
# from shim_threshold_integrator_coverage import start_coverage_monitor

async def setup_testbench(dut, clk_period=4, time_unit='ns'):
    tb = shim_threshold_integrator_base(dut, clk_period, time_unit)
    return tb

@cocotb.test()
async def test_reset(dut):
    tb = await setup_testbench(dut)
    tb.dut._log.info("STARTING TEST: test_reset")

    # First have the DUT at a known state
    await tb.reset()

    # Then start the monitor and scoreboard tasks
    state_transition_monitor_and_scoreboard_task = cocotb.start_soon(tb.state_transition_monitor_and_scoreboard())

    # Then apply the actual reset
    await tb.reset()

    # Give time to coroutines to finish and kill their tasks
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    state_transition_monitor_and_scoreboard_task.kill()


@cocotb.test()
async def test_idle_to_running(dut):
    tb = await setup_testbench(dut)
    tb.dut._log.info("STARTING TEST: test_idle_to_running")

    # First have the DUT at a known state
    await tb.reset()

    # Then start the monitor and scoreboard tasks
    state_transition_monitor_and_scoreboard_task = cocotb.start_soon(tb.state_transition_monitor_and_scoreboard())

    # Then apply the actual reset
    await tb.reset()

    await tb.idle_to_running_state()

    # Give time to coroutines to finish and kill their tasks
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    state_transition_monitor_and_scoreboard_task.kill()

@cocotb.test()
async def test_running_state(dut):
    tb = await setup_testbench(dut)
    tb.dut._log.info("STARTING TEST: test_running_state")

    # First have the DUT at a known state
    await tb.reset()

    # Then start the monitor and scoreboard tasks
    state_transition_monitor_and_scoreboard_task = cocotb.start_soon(tb.state_transition_monitor_and_scoreboard())

    # Then apply the actual reset
    await tb.reset()

    await tb.idle_to_running_state()

    await tb.running_state_model_and_scoreboard()

    # Give time to coroutines to finish and kill their tasks
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    state_transition_monitor_and_scoreboard_task.kill()