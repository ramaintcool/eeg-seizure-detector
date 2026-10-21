"""cocotb testbench: uses only top-level pins, so it also works for gate-level sim."""
import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

HERE = os.path.dirname(os.path.abspath(__file__))


@cocotb.test()
async def line_length_matches_model(dut):
    exp = json.load(open(os.path.join(HERE, "expected.json")))
    samples, exp_ll, exp_flags = exp["samples"], exp["ll"], exp["flags"]

    cocotb.start_soon(Clock(dut.clk, 100, units="ns").start())  # 10 MHz
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    got_ll, got_flags = [], []
    for x in samples:
        dut.ui_in.value = x
        dut.uio_in.value = 1          # sample_valid for one clock
        await RisingEdge(dut.clk)
        dut.uio_in.value = 0
        await RisingEdge(dut.clk)     # outputs from the previous edge visible
        out = int(dut.uo_out.value)
        if (out >> 1) & 1:            # window_done pulse
            got_ll.append((out >> 2) & 0x3F)   # ll_reg[9:4] on uo_out[7:2]
            got_flags.append(out & 1)
        await RisingEdge(dut.clk)     # one idle cycle between samples

    assert len(got_ll) == len(exp_ll), f"{len(got_ll)} windows vs {len(exp_ll)}"
    exp_ll = [(v >> 4) & 0x3F for v in exp_ll]   # only bits [9:4] are on pins
    bad = [i for i, (a, b) in enumerate(zip(got_ll, exp_ll)) if a != b]
    assert not bad, f"line-length mismatch in windows {bad[:5]}"
    assert got_flags == exp_flags, "seizure flag mismatch"
    dut._log.info(f"PASS: {len(got_ll)} windows match, "
                  f"{sum(got_flags)} flagged as seizure")
