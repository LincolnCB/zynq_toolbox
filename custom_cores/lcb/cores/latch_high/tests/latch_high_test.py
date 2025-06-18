import cocotb
from cocotb.triggers import RisingEdge, ReadOnly, ReadWrite
import random
from latch_high_base import latch_high_base
from latch_high_coverage import start_coverage_monitor

# Create a setup function that can be called by each test
async def setup_testbench(dut):
    tb = latch_high_base(dut, clk_period=4, time_unit="ns")
    return tb

# Check basic latching functionality, apply a pulse to din and check dout
@cocotb.test()
async def basic_test(dut):
    tb = await setup_testbench(dut)
    start_coverage_monitor(dut)
    await tb.reset()

    # Initial state check
    await ReadOnly()
    assert dut.dout.value == 0, f"ERROR: dout not 0 after reset. Expected 0, Got {dut.dout.value}"

    # Test 1: Latch a single bit high
    await RisingEdge(dut.clk)
    test_value_1 = 1 # _0001
    dut.din.value = test_value_1

    await ReadOnly()
    assert dut.dout.value == test_value_1, f"ERROR: Basic latching failed. Expected {test_value_1}, Got {dut.dout.value}"
    dut._log.info(f"Applied din: {test_value_1}, dout: {dut.dout.value}")

    # Test 2: Latch another bit while previous is still latched
    await RisingEdge(dut.clk)
    test_value_2 = 2 # _0010
    dut.din.value = test_value_2

    await ReadOnly()
    expected_dout = test_value_1 | test_value_2 # _0011
    assert dut.dout.value == expected_dout, "ERROR: Cumulative latching failed. Expected {expected_dout}, Got {dut.dout.value}"
    dut._log.info(f"Applied din: {test_value_2}, dout: {dut.dout.value}")

    # Test 3: din goes low, dout should remain latched high
    await RisingEdge(dut.clk)
    dut.din.value = 0

    await ReadOnly()
    assert dut.dout.value == expected_dout, f"ERROR: Latch not persistent. Expected {expected_dout}, Got {dut.dout.value}"
    dut._log.info(f"Applied din: 0, dout (should be persistent): {dut.dout.value}")

# Test latching functionality with random data over many cycles.
@cocotb.test()
async def random_test(dut):
    tb = await setup_testbench(dut)
    start_coverage_monitor(dut)
    await tb.reset()

    expected_dout = 0 # Initialize expected latch value

    num_cycles = 100
    for i in range(num_cycles):
        # Generate random input for din
        random_din = random.randint(0, tb.MAX_VALUE)

        # Drive din with random value
        await RisingEdge(dut.clk)
        dut.din.value = random_din
        expected_dout = expected_dout | random_din

        # Check output after propagation
        await ReadOnly()
        assert dut.dout.value == expected_dout, \
            f"ERROR at cycle {i}: Random test failed. " \
            f"din={random_din}, Expected dout={bin(expected_dout)}, Got dout={dut.dout.value}"
        dut._log.info(f"Cycle {i}: din={bin(dut.din.value)}, dout={bin(dut.dout.value)}, Expected={bin(expected_dout)}")

    dut._log.info(f"Completed {num_cycles} random test cycles.")

# Test that all bits can be latched high sequentially and simultaneously.
@cocotb.test()
async def latch_high_all_bits_test(dut):
    tb = await setup_testbench(dut)
    start_coverage_monitor(dut)
    await tb.reset()

    # Latch bits one by one
    expected_dout = 0

    for i in range(tb.WIDTH):
        single_bit_mask = 1 << i

        # Drive din with a single bit high at bit mask position i
        await RisingEdge(dut.clk)
        dut.din.value = single_bit_mask
        expected_dout = expected_dout | single_bit_mask

        # Sample
        await ReadOnly()
        assert dut.dout.value == expected_dout, \
            f"ERROR: Sequential latching of bit {i} failed. " \
            f"Expected {bin(expected_dout)}, Got {bin(dut.dout.value)}"
        dut._log.info(f"Latching bit {i}: din={bin(dut.din.value)}, dout={bin(dut.dout.value)}, expected={bin(expected_dout)}")

    # Verify all bits are latched high
    all_high = tb.MAX_VALUE

    await RisingEdge(dut.clk)
    dut.din.value = 0  # Set din to 0 to avoid further latching

    await ReadOnly()
    assert dut.dout.value == all_high, \
        f"ERROR: Not all bits latched high sequentially. Expected {bin(all_high)}, Got {bin(dut.dout.value)}"
    dut._log.info(f"All bits latched high sequentially: {bin(dut.dout.value)}")

# Test reset functionality to ensure latch is released.
@cocotb.test()
async def reset_functionality_test(dut):
    tb = await setup_testbench(dut)
    start_coverage_monitor(dut)
    await tb.reset()

    # Latch a single bit high
    await RisingEdge(dut.clk)
    test_value_1 = 1 # _0001
    dut.din.value = test_value_1
    expected_dout = test_value_1

    await ReadOnly()
    assert dut.dout.value == test_value_1, f"ERROR: Basic latching failed. Expected {bin(test_value_1)}, Got {dut.dout.value}"
    dut._log.info(f"Applied din: {bin(test_value_1)}, dout: {dut.dout.value}, expected: {bin(expected_dout)}")

    # Latch another bit while previous is still latched
    await RisingEdge(dut.clk)
    test_value_2 = 2 # _0010
    dut.din.value = test_value_2

    await ReadOnly()
    expected_dout = test_value_1 | test_value_2 # _0011
    assert dut.dout.value == expected_dout, "ERROR: Cumulative latching failed. Expected {expected_dout}, Got {dut.dout.value}"
    dut._log.info(f"Applied din: {bin(test_value_2)}, dout: {dut.dout.value}, expected: {bin(expected_dout)}")

    # Release the latch with reset, dout should now be test_value_2 only.
    await tb.reset()  # Reset the DUT
    await ReadOnly()
    expected_dout = test_value_2
    assert dut.dout.value == expected_dout, f"ERROR: Latch did not release after reset. Expected {bin(expected_dout)}, Got {dut.dout.value}"
