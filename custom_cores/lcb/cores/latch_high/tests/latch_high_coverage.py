import cocotb
from cocotb.triggers import RisingEdge, ReadOnly
from cocotb_coverage.coverage import *
import atexit
import os

# Should match the WIDTH parameter in the DUT.
WIDTH = 32

# Coverage points for din and dout signals
@CoverPoint("latch_high.din",
            xf=lambda dut: int(dut.din.value),
            bins=range(0, 1),
            at_least=1)
@CoverPoint("latch_high.dout",
            xf=lambda dut: int(dut.dout.value),
            bins=range(0, 1),
            at_least=1)
def sample_din_dout(dut):
    pass

async def _coverage_monitor(dut):
    await RisingEdge(dut.clk)
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        sample_din_dout(dut)

def start_coverage_monitor(dut):
    cocotb.start_soon(_coverage_monitor(dut))

def write_report():
    results_dir = os.getenv("RESULTS_ROOT_DIR", ".") # Default to current dir if not set

    original_cwd = os.getcwd() # Store the original working directory

    try:
        # Change the current working directory to the results directory
        os.makedirs(results_dir, exist_ok=True) # Ensure the directory exists
        os.chdir(results_dir)
        cocotb.log.info(f"Changing CWD to: {os.getcwd()}") # Log the change

        # Now, export the coverage reports.
        # These functions will write to the new current working directory.
        coverage_db.export_to_xml("latch_high_coverage.xml")
        coverage_db.export_to_yaml("latch_high_coverage.yaml")

    finally:
        # Change back to the original working directory to avoid affecting other parts
        # of the cocotb environment or subsequent processes, although for atexit
        # this might be less critical as the process is exiting.
        os.chdir(original_cwd)
        cocotb.log.info(f"Restored CWD to: {os.getcwd()}")


atexit.register(write_report)