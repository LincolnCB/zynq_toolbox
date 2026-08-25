import cocotb
from cocotb.triggers import RisingEdge, ReadOnly
import random
from axi_rate_gen_base import axi_rate_gen_base


async def setup(dut):
    return axi_rate_gen_base(dut, clk_period=10, time_unit="ns")


@cocotb.test()
async def test_reset(dut):
    tb = await setup(dut)
    await tb.reset()
    await ReadOnly()
    assert int(dut.sts.value) == 0, "BEAT_COUNT should be 0 after reset"
    assert dut.m_axis_tvalid.value == 0, "No output should be valid after reset"


@cocotb.test()
async def test_full_rate_passthrough(dut):
    """rate_div=0: every beat passes unchanged, order and tlast preserved."""
    tb = await setup(dut)
    await tb.reset()
    tb.set_cfg(rate_div=0, pause=0)

    n = 32
    words = [random.randint(0, tb.DATA_MASK) for _ in range(n)]
    received = await tb.send_and_receive(words, dest=3)

    assert len(received) == n, f"Expected {n} beats, got {len(received)}"
    for i, (data, last) in enumerate(received):
        assert data == words[i], f"Data mismatch at {i}: got 0x{data:X}, want 0x{words[i]:X}"
        assert last == (1 if i == n - 1 else 0), f"tlast mismatch at beat {i}"

    await ReadOnly()
    assert int(dut.sts.value) == n, f"BEAT_COUNT should be {n}, got {int(dut.sts.value)}"


@cocotb.test()
async def test_rate_limit_spacing(dut):
    """rate_div=R spaces beats exactly R+1 cycles apart with data always ready."""
    tb = await setup(dut)
    for rate_div in (1, 3, 7):
        await tb.reset()
        tb.set_cfg(rate_div=rate_div, pause=0)

        n = 8
        words = [i + 1 for i in range(n)]
        beat_cycles = []

        async def driver():
            idx = 0
            while idx < n:
                dut.s_axis_tdata.value = words[idx]
                dut.s_axis_tlast.value = 1 if idx == n - 1 else 0
                dut.s_axis_tvalid.value = 1
                await ReadOnly()
                fired = (dut.s_axis_tvalid.value == 1 and dut.s_axis_tready.value == 1)
                await RisingEdge(dut.aclk)
                if fired:
                    idx += 1
            dut.s_axis_tvalid.value = 0

        drv = cocotb.start_soon(driver())
        cycle = 0
        while len(beat_cycles) < n:
            dut.m_axis_tready.value = 1
            await ReadOnly()
            if dut.m_axis_tvalid.value == 1 and dut.m_axis_tready.value == 1:
                beat_cycles.append(cycle)
            await RisingEdge(dut.aclk)
            cycle += 1
        dut.m_axis_tready.value = 0
        await drv

        gaps = [beat_cycles[i + 1] - beat_cycles[i] for i in range(len(beat_cycles) - 1)]
        assert all(g == rate_div + 1 for g in gaps), \
            f"rate_div={rate_div}: expected all gaps {rate_div + 1}, got {gaps}"


@cocotb.test()
async def test_pause_holds_stream(dut):
    """PAUSE freezes forwarding; data resumes intact when released."""
    tb = await setup(dut)
    await tb.reset()
    tb.set_cfg(rate_div=0, pause=1)

    # Offer data while paused: nothing should pass.
    dut.s_axis_tdata.value = 0xABCD1234
    dut.s_axis_tdest.value = 1
    dut.s_axis_tlast.value = 0
    dut.s_axis_tvalid.value = 1
    dut.m_axis_tready.value = 1
    for _ in range(10):
        await ReadOnly()
        assert dut.m_axis_tvalid.value == 0, "No beat should pass while paused"
        assert dut.s_axis_tready.value == 0, "Slave should backpressure while paused"
        await RisingEdge(dut.aclk)
    await ReadOnly()
    assert int(dut.sts.value) == 0, "BEAT_COUNT should stay 0 while paused"

    # Release pause and finish a short transfer (step off the ReadOnly phase first).
    await RisingEdge(dut.aclk)
    dut.s_axis_tvalid.value = 0
    await RisingEdge(dut.aclk)
    tb.set_cfg(rate_div=0, pause=0)
    words = [0x11111111, 0x22222222, 0x33333333]
    received = await tb.send_and_receive(words, dest=1)
    assert [d for d, _ in received] == words, f"Data after resume mismatch: {received}"


@cocotb.test()
async def test_backpressure_no_loss(dut):
    """A stalled master (tready low) must not drop or duplicate beats."""
    tb = await setup(dut)
    await tb.reset()
    tb.set_cfg(rate_div=0, pause=0)

    n = 16
    words = [random.randint(0, tb.DATA_MASK) for _ in range(n)]
    received = []

    async def driver():
        idx = 0
        while idx < n:
            dut.s_axis_tdata.value = words[idx]
            dut.s_axis_tlast.value = 1 if idx == n - 1 else 0
            dut.s_axis_tvalid.value = 1
            await ReadOnly()
            fired = (dut.s_axis_tvalid.value == 1 and dut.s_axis_tready.value == 1)
            await RisingEdge(dut.aclk)
            if fired:
                idx += 1
        dut.s_axis_tvalid.value = 0

    drv = cocotb.start_soon(driver())
    cycle = 0
    while len(received) < n and cycle < 10000:
        # Randomly stall the consumer.
        dut.m_axis_tready.value = 1 if random.random() > 0.5 else 0
        await ReadOnly()
        if dut.m_axis_tvalid.value == 1 and dut.m_axis_tready.value == 1:
            received.append(int(dut.m_axis_tdata.value))
        await RisingEdge(dut.aclk)
        cycle += 1
    dut.m_axis_tready.value = 0
    await drv

    assert received == words, "Backpressure corrupted the stream"
