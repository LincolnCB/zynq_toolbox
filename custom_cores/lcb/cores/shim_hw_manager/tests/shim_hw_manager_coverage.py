import cocotb
from cocotb.triggers import RisingEdge, ReadOnly
from cocotb_coverage.coverage import *
import atexit
import os

STATE_BIN_LABELS = {
    1: "IDLE",
    2: "CONFIRM_SPI_INIT",
    3: "RELEASE_SD_F",
    4: "PULSE_SD_RST",
    5: "SD_RST_DELAY",
    6: "CONFIRM_SPI_START",
    7: "RUNNING",
    8: "HALTED"
}

STATUS_BIN_LABELS = {
    0:    "STATUS_EMPTY",
    1:    "STATUS_OK",
    2:    "STATUS_PS_SHUTDOWN",
    256:  "STATUS_SPI_START_TIMEOUT",
    257:  "STATUS_SPI_INIT_TIMEOUT",
    512:  "STATUS_INTEG_THRESH_AVG_OOB",
    513:  "STATUS_INTEG_WINDOW_OOB",
    514:  "STATUS_INTEG_EN_OOB",
    515:  "STATUS_SYS_EN_OOB",
    516:  "STATUS_LOCK_VIOL",
    768:  "STATUS_SHUTDOWN_SENSE",
    769:  "STATUS_EXT_SHUTDOWN",
    1024: "STATUS_OVER_THRESH",
    1025: "STATUS_THRESH_UNDERFLOW",
    1026: "STATUS_THRESH_OVERFLOW",
    1280: "STATUS_BAD_TRIG_CMD",
    1281: "STATUS_TRIG_BUF_OVERFLOW",
    1536: "STATUS_BAD_DAC_CMD",
    1537: "STATUS_DAC_CAL_OOB",
    1538: "STATUS_DAC_VAL_OOB",
    1539: "STATUS_DAC_BUF_UNDERFLOW",
    1540: "STATUS_DAC_BUF_OVERFLOW",
    1541: "STATUS_UNEXP_DAC_TRIG",
    1792: "STATUS_BAD_ADC_CMD",
    1793: "STATUS_ADC_BUF_UNDERFLOW",
    1794: "STATUS_ADC_BUF_OVERFLOW",
    1795: "STATUS_ADC_DATA_BUF_UNDERFLOW",
    1796: "STATUS_ADC_DATA_BUF_OVERFLOW",
    1797: "STATUS_UNEXP_ADC_TRIG",
}

# Coverage points for states and status codes
@CoverPoint("shim_hw_manager.state",
            xf = lambda dut: int(dut.state.value),
            bins = list(STATE_BIN_LABELS.keys()),
            bins_labels = list(STATE_BIN_LABELS.values()),
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.status_code",
            xf = lambda dut: dut.status_code.value,
            bins = list(STATUS_BIN_LABELS.keys()),
            bins_labels = list(STATUS_BIN_LABELS.values()),
            rel = lambda x, y: x == y,
            at_least = 1)
def sample_state_and_status_coverage(dut):
    pass

# Coverage points for system control signals
@CoverPoint("shim_hw_manager.sys_en",
            xf = lambda dut: int(dut.sys_en.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.spi_off",
            xf = lambda dut: int(dut.spi_off.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.ext_shutdown",
            xf = lambda dut: int(dut.ext_shutdown.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.unlock_cfg",
            xf = lambda dut: int(dut.unlock_cfg.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.spi_clk_power_n",
            xf = lambda dut: int(dut.spi_clk_power_n.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.spi_en",
            xf = lambda dut: int(dut.spi_en.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.shutdown_sense_en",
            xf = lambda dut: int(dut.shutdown_sense_en.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.trig_en",
            xf = lambda dut: int(dut.trig_en.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.n_shutdown_force",
            xf = lambda dut: int(dut.n_shutdown_force.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.n_shutdown_rst",
            xf = lambda dut: int(dut.n_shutdown_rst.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
def sample_system_control_coverage(dut):
    pass

# Coverage points for per-board signals
@CoverPoint("shim_hw_manager.shutdown_sense",
            xf = lambda dut: int(dut.shutdown_sense.value),
            bins = [0, 1, 2, 4, 8, 32, 64, 128],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.over_thresh",
            xf = lambda dut: int(dut.over_thresh.value),
            bins = [0, 1, 2, 4, 8, 32, 64, 128],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.thresh_underflow",
            xf = lambda dut: int(dut.thresh_underflow.value),
            bins = [0, 1, 2, 4, 8, 32, 64, 128],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.thresh_overflow",
            xf = lambda dut: int(dut.thresh_overflow.value),
            bins = [0, 1, 2, 4, 8, 32, 64, 128],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.bad_dac_cmd",
            xf = lambda dut: int(dut.bad_dac_cmd.value),
            bins = [0, 1, 2, 4, 8, 32, 64, 128],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.dac_cal_oob",
            xf = lambda dut: int(dut.dac_cal_oob.value),
            bins = [0, 1, 2, 4, 8, 32, 64, 128],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.dac_val_oob",
            xf = lambda dut: int(dut.dac_val_oob.value),
            bins = [0, 1, 2, 4, 8, 32, 64, 128],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.dac_cmd_buf_underflow",
            xf = lambda dut: int(dut.dac_cmd_buf_underflow.value),
            bins = [0, 1, 2, 4, 8, 32, 64, 128],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.dac_cmd_buf_overflow",
            xf = lambda dut: int(dut.dac_cmd_buf_overflow.value),
            bins = [0, 1, 2, 4, 8, 32, 64, 128],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.unexp_dac_trig",
            xf = lambda dut: int(dut.unexp_dac_trig.value),
            bins = [0, 1, 2, 4, 8, 32, 64, 128],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.bad_adc_cmd",
            xf = lambda dut: int(dut.bad_adc_cmd.value),
            bins = [0, 1, 2, 4, 8, 32, 64, 128],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.adc_cmd_buf_underflow",
            xf = lambda dut: int(dut.adc_cmd_buf_underflow.value),
            bins = [0, 1, 2, 4, 8, 32, 64, 128],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.adc_cmd_buf_overflow",
            xf = lambda dut: int(dut.adc_cmd_buf_overflow.value),
            bins = [0, 1, 2, 4, 8, 32, 64, 128],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.adc_data_buf_underflow",
            xf = lambda dut: int(dut.adc_data_buf_underflow.value),
            bins = [0, 1, 2, 4, 8, 32, 64, 128],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.adc_data_buf_overflow",
            xf = lambda dut: int(dut.adc_data_buf_overflow.value),
            bins = [0, 1, 2, 4, 8, 32, 64, 128],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.unexp_adc_trig",
            xf = lambda dut: int(dut.unexp_adc_trig.value),
            bins = [0, 1, 2, 4, 8, 32, 64, 128],
            rel = lambda x, y: x == y,
            at_least = 1)
def sample_per_board_signals_coverage(dut):
    pass

# Coverage points for configuration and status signals
@CoverPoint("shim_hw_manager.integ_thresh_avg_oob",
            xf = lambda dut: int(dut.integ_thresh_avg_oob.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.integ_window_oob",
            xf = lambda dut: int(dut.integ_window_oob.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.integ_en_oob",
            xf = lambda dut: int(dut.integ_en_oob.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.sys_en_oob",
            xf = lambda dut: int(dut.sys_en_oob.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.lock_viol",
            xf = lambda dut: int(dut.lock_viol.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
def sample_configuration_status_signals_coverage(dut):
    pass

# Coverage points for trigger buffer and command signals
@CoverPoint("shim_hw_manager.bad_trig_cmd",
            xf = lambda dut: int(dut.bad_trig_cmd.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverPoint("shim_hw_manager.trig_buf_overflow",
            xf = lambda dut: int(dut.trig_buf_overflow.value),
            bins = [True, False],
            rel = lambda x, y: x == y,
            at_least = 1)
def sample_trigger_buf_and_cmd_coverage(dut):
    pass

# PS interrupt cross coverage
@CoverPoint("shim_hw_manager.ps_interrupt",
            xf = lambda dut: int(dut.ps_interrupt.value),
            bins = [True, False],
            bins_labels = ["PS Interrupt Active", "PS Interrupt Inactive"],
            rel = lambda x, y: x == y,
            at_least = 1)
@CoverCross("shim_hw_manager.ps_interrupt_cross",
            items = ["shim_hw_manager.state", "shim_hw_manager.ps_interrupt"],
            ign_bins= [ ("RELEASE_SD_F", None),
                        ("PULSE_SD_RST", None),
                        ("SD_RST_DELAY", None), 
                        ("CONFIRM_SPI_INIT", None), 
                        ("CONFIRM_SPI_START", None),
                        ("IDLE", None)])
def sample_ps_interrupt_cross_coverage(dut):
    pass
            

async def _coverage_monitor(dut):
    await RisingEdge(dut.clk)
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        sample_state_and_status_coverage(dut)
        sample_system_control_coverage(dut)
        sample_per_board_signals_coverage(dut)
        sample_configuration_status_signals_coverage(dut)
        sample_trigger_buf_and_cmd_coverage(dut)
        sample_ps_interrupt_cross_coverage(dut)

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
        coverage_db.export_to_xml("shim_hw_manager_coverage.xml")
        coverage_db.export_to_yaml("shim_hw_manager_coverage.yaml")

    finally:
        # Change back to the original working directory to avoid affecting other parts
        # of the cocotb environment or subsequent processes, although for atexit
        # this might be less critical as the process is exiting.
        os.chdir(original_cwd)
        cocotb.log.info(f"Restored CWD to: {os.getcwd()}")

atexit.register(write_report)
