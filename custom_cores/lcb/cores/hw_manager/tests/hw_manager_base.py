import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.regression import TestFactory
from cocotb.result import TestFailure

class hw_manager_base:
    """
    Hardware Manager cocotb Base Class
    """

    # State encoding dictionary
    STATES = {
        1: "IDLE",
        2: "RELEASE_SD_F",
        3: "PULSE_SD_RST",
        4: "SD_RST_DELAY",
        5: "START_DMA",
        6: "START_SPI",
        7: "RUNNING",
        8: "HALTED"
    }
    
    # Status codes dictionary
    STATUS_CODES = {
        1: "STATUS_OK",
        2: "STATUS_PS_SHUTDOWN",
        3: "STATUS_TRIG_LOCKOUT_OOB",
        4: "STATUS_CAL_OFFSET_OOB",
        5: "STATUS_DAC_DIVIDER_OOB",
        6: "STATUS_INTEG_THRESH_AVG_OOB",
        7: "STATUS_INTEG_WINDOW_OOB",
        8: "STATUS_INTEG_EN_OOB",
        9: "STATUS_SYS_EN_OOB",
        10: "STATUS_LOCK_VIOL",
        11: "STATUS_SHUTDOWN_SENSE",
        12: "STATUS_EXT_SHUTDOWN",
        13: "STATUS_DAC_OVER_THRESH",
        14: "STATUS_ADC_OVER_THRESH",
        15: "STATUS_DAC_THRESH_UNDERFLOW",
        16: "STATUS_DAC_THRESH_OVERFLOW",
        17: "STATUS_ADC_THRESH_UNDERFLOW",
        18: "STATUS_ADC_THRESH_OVERFLOW",
        19: "STATUS_DAC_BUF_UNDERFLOW",
        20: "STATUS_DAC_BUF_OVERFLOW",
        21: "STATUS_ADC_BUF_UNDERFLOW",
        22: "STATUS_ADC_BUF_OVERFLOW",
        23: "STATUS_PREMAT_DAC_TRIG",
        24: "STATUS_PREMAT_ADC_TRIG",
        25: "STATUS_PREMAT_DAC_DIV",
        26: "STATUS_PREMAT_ADC_DIV",
        27: "STATUS_DAC_BUF_FILL_TIMEOUT",
        28: "STATUS_SPI_START_TIMEOUT"
    }

    def __init__(self, dut, clk_period = 4, time_unit = "ns", 
                 SHUTDOWN_FORCE_DELAY = 25000000,
                 SHUTDOWN_RESET_PULSE = 25000,
                 SHUTDOWN_RESET_DELAY = 25000000,
                 BUF_LOAD_WAIT = 25000000,
                 SPI_START_WAIT = 25000000
                 ):
        """
        Initialize the testbench
        
        Args:
            dut: The Verilog/VHDL design under test
        """
        self.time_unit = time_unit
        
        self.SHUTDOWN_FORCE_DELAY = SHUTDOWN_FORCE_DELAY
        self.SHUTDOWN_RESET_PULSE = SHUTDOWN_RESET_PULSE
        self.SHUTDOWN_RESET_DELAY = SHUTDOWN_RESET_DELAY
        self.BUF_LOAD_WAIT = BUF_LOAD_WAIT
        self.SPI_START_WAIT = SPI_START_WAIT
        
        self.clk_period = clk_period
        self.dut = dut
        
        # Create clock
        cocotb.start_soon(Clock(self.dut.clk, clk_period, units=time_unit).start())  # Default is 250 MHz clock
        
        # Set default values
        self.dut.sys_en.value = 0
        self.dut.dac_buf_loaded.value = 0
        self.dut.spi_running.value = 0
        self.dut.ext_shutdown.value = 0
        # Configuration values
        self.dut.trig_lockout_oob.value = 0
        self.dut.cal_offset_oob.value = 0
        self.dut.dac_divider_oob.value = 0
        self.dut.integ_thresh_avg_oob.value = 0
        self.dut.integ_window_oob.value = 0
        self.dut.integ_en_oob.value = 0
        self.dut.sys_en_oob.value = 0
        self.dut.lock_viol.value = 0
        # Shutdown sense
        self.dut.shutdown_sense.value = 0
        # Integrator errors (all boards)
        self.dut.dac_over_thresh.value = 0
        self.dut.adc_over_thresh.value = 0
        self.dut.dac_thresh_underflow.value = 0
        self.dut.dac_thresh_overflow.value = 0
        self.dut.adc_thresh_underflow.value = 0
        self.dut.adc_thresh_overflow.value = 0
        # DAC/ADC errors (all boards)
        self.dut.dac_buf_underflow.value = 0
        self.dut.dac_buf_overflow.value = 0
        self.dut.adc_buf_underflow.value = 0
        self.dut.adc_buf_overflow.value = 0
        self.dut.premat_dac_trig.value = 0
        self.dut.premat_adc_trig.value = 0
        self.dut.premat_dac_div.value = 0
        self.dut.premat_adc_div.value = 0

    def get_state_name(self, state_value):
        """Convert state value to state name"""
        # Convert BinaryValue to int
        state_int = int(state_value)
        return self.STATES.get(state_int, f"UNKNOWN_STATE({state_int})")

    def get_status_name(self, status_value):
        """Convert status code value to status name"""
        # Convert BinaryValue to int
        status_int = int(status_value)
        return self.STATUS_CODES.get(status_int, f"UNKNOWN_STATUS({status_int})")
    
    def get_board_num_from_status_word(self, status_word):
        """Extract board number from status word"""
        # Convert BinaryValue to int
        status_word_int = int(status_word)
        return (status_word_int >> 29) & 0x7
    
    def extract_state_and_status(self):
        """Extract and decode state and status from the DUT"""
        state_val = int(self.dut.state.value)  # Convert to int
        status_word = int(self.dut.status_word.value)  # Convert to int
        status_code = (status_word >> 4) & 0x1FFFFFF
        board_num = (status_word >> 29) & 0x7
        
        state_name = self.get_state_name(state_val)
        status_name = self.get_status_name(status_code)
        
        return {
            "state_value": state_val,
            "state_name": state_name,
            "status_code": status_code,
            "status_name": status_name,
            "board_num": board_num,
            "status_word": status_word
        }
    
    def print_current_status(self):
        """Print the current status information in a human-readable format"""
        status_info = self.extract_state_and_status()
        time = cocotb.utils.get_sim_time(units=self.time_unit)
        
        self.dut._log.info(f"------------ CURRENT STATUS AT TIME = {time}  ------------")
        self.dut._log.info(f"State: {status_info['state_name']} ({status_info['state_value']})")
        self.dut._log.info(f"Status: {status_info['status_name']} ({status_info['status_code']})")
        if status_info['board_num'] > 0:
            self.dut._log.info(f"Board: {status_info['board_num']}")
        self.dut._log.info("------------ OUTPUT SIGNALS AT TIME = {time}  ------------")
        self.dut._log.info(f"  sys_rst: {self.dut.sys_rst.value}")
        self.dut._log.info(f"  n_shutdown_force: {self.dut.n_shutdown_force.value}")
        self.dut._log.info(f"  n_shutdown_rst: {self.dut.n_shutdown_rst.value}")
        self.dut._log.info(f"  dma_en: {self.dut.dma_en.value}")
        self.dut._log.info(f"  spi_en: {self.dut.spi_en.value}")
        self.dut._log.info(f"  trig_en: {self.dut.trig_en.value}")
        self.dut._log.info(f"  ps_interrupt: {self.dut.ps_interrupt.value}")
        self.dut._log.info("---------------------------------------------")

    async def reset(self):
        """Reset the DUT"""
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        self.dut._log.info("RESET COMPLETE")

    async def check_state_and_status(self, expected_state, expected_status_code, expected_board_num=0):
        """Check the status outputs and the state of the hardware manager"""
        status_info = self.extract_state_and_status()
        state = status_info["state_value"]
        status_code = status_info["status_code"]
        board_num = status_info["board_num"]
        time = cocotb.utils.get_sim_time(units=self.time_unit)
        
        self.dut._log.info(f"------------EXPECTED STATUS AT TIME = {time} ------------")
        self.dut._log.info(f"Expected State: {self.get_state_name(expected_state)} ({expected_state})")
        self.dut._log.info(f"Expected Status: {self.get_status_name(expected_status_code)} ({expected_status_code})")
        if expected_board_num > 0:
            self.dut._log.info(f"Expected Board: {expected_board_num}")
        # Log current status at the same time
        self.print_current_status()
        
        # Pass the test if the state and status match the expected values
        assert state == expected_state, f"Expected state {self.get_state_name(expected_state)}({expected_state}), " \
            f"got {self.get_state_name(state)}({state})"
        
        assert status_code == expected_status_code, f"Expected status code {self.get_status_name(expected_status_code)}({expected_status_code}), " \
            f"got {self.get_status_name(status_code)}({status_code})"
        
        assert board_num == expected_board_num, f"Expected board number {expected_board_num}, got {board_num}"

        return state, status_code, board_num
    
    async def check_state(self, expected_state):
        """Check the state of the hardware manager"""
        status_info = self.extract_state_and_status()
        state = status_info["state_value"]
        
        # Pass the test if the state matches the expected value
        assert state == expected_state, f"Expected state {self.get_state_name(expected_state)}({expected_state}), " \
            f"got {self.get_state_name(state)}({state})"
        
        return state
    
    async def wait_cycles(self, cycles):
        """Wait for specified number of clock cycles"""
        for _ in range(cycles):
            await RisingEdge(self.dut.clk)

    async def wait_for_state(self, expected_state, timeout_ns=1000000, allow_intermediate_states=False, max_wait_cycles=None):
        """Wait until the state machine reaches a specific state

        Args:
        expected_state: The state value to wait for
        timeout_ns: Maximum time to wait in nanoseconds before failing
        allow_intermediate_states: If True, allows the state to change to other states before reaching expected_state
        max_wait_cycles: Optional maximum number of cycles to wait, overrides timeout_ns if specified
        """
        expected_state_name = self.get_state_name(expected_state)
        self.dut._log.info(f"Waiting for state: {expected_state_name}({expected_state})")

        # Calculate max cycles based on either max_wait_cycles or timeout_ns
        max_cycles = max_wait_cycles if max_wait_cycles is not None else (timeout_ns // 4)

        # Track the current state for logging purposes
        last_state = None
        last_state_name = None
        inital_state = self.dut.state.value

        for i in range(max_cycles):
            await RisingEdge(self.dut.clk)

            current_state = self.dut.state.value

            # Log state transitions for debugging
            if current_state != last_state and last_state is not None:
                last_state = current_state
                last_state_name = self.get_state_name(current_state)
                self.dut._log.info(f"State changed to {last_state_name}({int(current_state)}) at cycle {i}")

            if current_state == expected_state:
                self.dut._log.info(f"Reached state {expected_state_name}({expected_state}) after {i} cycles")
                return

            # If not allowing intermediate states, fail if state changes to something other than expected
            if not allow_intermediate_states and i > 0 and current_state != inital_state:
                assert current_state == expected_state, \
                    f"Reached unexpected state {last_state_name}({current_state}) while waiting for {expected_state_name}({expected_state})"
            
        # If we reach here, we timed out waiting for the expected state
        self.dut._log.info(f"BEFORE FAILURE:")
        self.print_current_status()  # Print final status before failure
        assert False, f"Timeout waiting for state {expected_state_name}({expected_state}) after {max_cycles} cycles"

