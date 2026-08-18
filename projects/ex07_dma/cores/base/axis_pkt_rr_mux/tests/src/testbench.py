"""cocotb testbench for axis_pkt_rr_mux.

The core merges NUM_SI (= 4) AXI4-Stream slave inputs onto one master output with
packet-atomic, round-robin arbitration: once a slave is granted it keeps the
master until its TLAST beat is accepted, then arbitration moves on. These tests
check exactly the properties ex07's MCDMA S2MM path needs:

  * a granted packet's beats are never interleaved with another channel's,
  * TDATA/TDEST/TLAST pass through unchanged,
  * no continuously-active channel starves the others (round-robin fairness),
  * all of the above hold under master-side backpressure.

Each source channel `ch` emits words encoded as (ch << 24) | (pkt << 8) | idx and
sets TDEST = ch, so the master monitor can reconstruct which source and packet
every beat came from and assert atomicity independently of timing.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly
import random

NUM_SI = 4


def encode(ch, pkt, idx):
    return ((ch & 0xFF) << 24) | ((pkt & 0xFFFF) << 8) | (idx & 0xFF)


async def reset(dut):
    dut.aresetn.value = 0
    for ch in range(NUM_SI):
        getattr(dut, f"s0{ch}_axis_tvalid").value = 0
        getattr(dut, f"s0{ch}_axis_tdata").value = 0
        getattr(dut, f"s0{ch}_axis_tdest").value = 0
        getattr(dut, f"s0{ch}_axis_tlast").value = 0
    dut.m_axis_tready.value = 0
    for _ in range(3):
        await RisingEdge(dut.aclk)
    dut.aresetn.value = 1
    await RisingEdge(dut.aclk)


async def send_packet(dut, ch, pkt, length):
    """Drive one packet of `length` beats out of slave `ch`."""
    v = getattr(dut, f"s0{ch}_axis_tvalid")
    r = getattr(dut, f"s0{ch}_axis_tready")
    d = getattr(dut, f"s0{ch}_axis_tdata")
    dest = getattr(dut, f"s0{ch}_axis_tdest")
    last = getattr(dut, f"s0{ch}_axis_tlast")
    for idx in range(length):
        v.value = 1
        d.value = encode(ch, pkt, idx)
        dest.value = ch
        last.value = 1 if idx == length - 1 else 0
        await ReadOnly()
        while r.value != 1:
            await RisingEdge(dut.aclk)
            await ReadOnly()
        await RisingEdge(dut.aclk)
    v.value = 0
    last.value = 0


async def master_ready_driver(dut, accept_prob):
    """Continuously drive m_axis_tready (random backpressure when < 1.0)."""
    while True:
        dut.m_axis_tready.value = 1 if random.random() < accept_prob else 0
        await RisingEdge(dut.aclk)


async def master_monitor(dut, beats):
    """Record every accepted master beat as (data, dest, last)."""
    while True:
        await RisingEdge(dut.aclk)
        await ReadOnly()
        if dut.m_axis_tvalid.value == 1 and dut.m_axis_tready.value == 1:
            beats.append((int(dut.m_axis_tdata.value),
                          int(dut.m_axis_tdest.value),
                          int(dut.m_axis_tlast.value)))


def assemble_packets(beats):
    """Split a flat beat list into packets on TLAST and assert atomicity."""
    packets = []
    current = []
    for data, dest, last in beats:
        current.append((data, dest))
        if last:
            packets.append(current)
            current = []
    assert not current, "trailing beats with no TLAST -- a packet never closed"

    for pkt in packets:
        src = pkt[0][1]
        ch_from_data = (pkt[0][0] >> 24) & 0xFF
        pkt_id = (pkt[0][0] >> 8) & 0xFFFF
        assert ch_from_data == src, (
            f"beat data source {ch_from_data} != TDEST {src} (interleaving/misroute)")
        for idx, (data, dest) in enumerate(pkt):
            assert dest == src, f"TDEST changed mid-packet: {dest} != {src} (interleaved)"
            assert data == encode(src, pkt_id, idx), (
                f"beat {idx} of ch{src} pkt{pkt_id} = 0x{data:08x}, "
                f"expected 0x{encode(src, pkt_id, idx):08x}")
    return packets


@cocotb.test()
async def test_reset(dut):
    cocotb.start_soon(Clock(dut.aclk, 10, units="ns").start())
    await reset(dut)
    await ReadOnly()
    assert dut.m_axis_tvalid.value == 0, "master must be idle after reset"


@cocotb.test()
async def test_single_channel(dut):
    cocotb.start_soon(Clock(dut.aclk, 10, units="ns").start())
    await reset(dut)
    beats = []
    cocotb.start_soon(master_monitor(dut, beats))
    dut.m_axis_tready.value = 1

    await send_packet(dut, 2, pkt=0, length=8)
    for _ in range(5):
        await RisingEdge(dut.aclk)

    packets = assemble_packets(beats)
    assert len(packets) == 1, f"expected 1 packet, got {len(packets)}"
    assert len(packets[0]) == 8, "packet length mismatch"
    assert packets[0][0][1] == 2, "wrong TDEST forwarded"


@cocotb.test()
async def test_all_channels_atomic(dut):
    """All four slaves present a packet at once; each must arrive whole."""
    cocotb.start_soon(Clock(dut.aclk, 10, units="ns").start())
    await reset(dut)
    beats = []
    cocotb.start_soon(master_monitor(dut, beats))
    dut.m_axis_tready.value = 1

    senders = [cocotb.start_soon(send_packet(dut, ch, pkt=0, length=6))
               for ch in range(NUM_SI)]
    for s in senders:
        await s.join()
    for _ in range(10):
        await RisingEdge(dut.aclk)

    packets = assemble_packets(beats)
    assert len(packets) == NUM_SI, f"expected {NUM_SI} packets, got {len(packets)}"
    seen = sorted(pkt[0][1] for pkt in packets)
    assert seen == list(range(NUM_SI)), f"channels delivered {seen}, expected all"


@cocotb.test()
async def test_backpressure(dut):
    """Same as atomic, but with random master-side backpressure."""
    random.seed(1)
    cocotb.start_soon(Clock(dut.aclk, 10, units="ns").start())
    await reset(dut)
    beats = []
    cocotb.start_soon(master_monitor(dut, beats))
    cocotb.start_soon(master_ready_driver(dut, accept_prob=0.55))

    senders = [cocotb.start_soon(send_packet(dut, ch, pkt=0, length=7))
               for ch in range(NUM_SI)]
    for s in senders:
        await s.join()
    for _ in range(20):
        await RisingEdge(dut.aclk)

    packets = assemble_packets(beats)
    assert len(packets) == NUM_SI, f"expected {NUM_SI} packets, got {len(packets)}"
    seen = sorted(pkt[0][1] for pkt in packets)
    assert seen == list(range(NUM_SI)), f"channels delivered {seen}, expected all"


@cocotb.test()
async def test_round_robin_fairness(dut):
    """A greedy channel must not starve the others."""
    cocotb.start_soon(Clock(dut.aclk, 10, units="ns").start())
    await reset(dut)
    beats = []
    cocotb.start_soon(master_monitor(dut, beats))
    dut.m_axis_tready.value = 1

    # ch0 floods packets back-to-back; ch1 and ch3 each send a few.
    async def flood(ch, n, length):
        for pkt in range(n):
            await send_packet(dut, ch, pkt, length)

    tasks = [
        cocotb.start_soon(flood(0, 6, 4)),
        cocotb.start_soon(flood(1, 3, 4)),
        cocotb.start_soon(flood(3, 3, 4)),
    ]
    for t in tasks:
        await t.join()
    for _ in range(20):
        await RisingEdge(dut.aclk)

    packets = assemble_packets(beats)
    counts = {ch: 0 for ch in range(NUM_SI)}
    for pkt in packets:
        counts[pkt[0][1]] += 1
    assert counts[0] == 6, f"ch0 delivered {counts[0]}/6"
    assert counts[1] == 3, f"ch1 starved: {counts[1]}/3"
    assert counts[3] == 3, f"ch3 starved: {counts[3]}/3"
    assert counts[2] == 0, "ch2 sent nothing but packets appeared"
