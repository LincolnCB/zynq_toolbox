import cocotb
from cocotb.triggers import RisingEdge , Timer
from hw_manager_base import hw_manager_base


# Create a setup function that can be called by each test
async def setup_testbench(dut):
    # Delay parameters should be the same with hw_manager.v
    tb = hw_manager_base(dut, clk_period=4, time_unit="ns",
                        SHUTDOWN_FORCE_DELAY=250,
                        SHUTDOWN_RESET_PULSE=25,
                        SHUTDOWN_RESET_DELAY=250,
                        BUF_LOAD_WAIT=2500,
                        SPI_START_WAIT=2500)
    return tb

# Helper function to set up the testbench and got to RUNNING state
async def normal_start_up_with_no_log(dut):
    tb = await setup_testbench(dut)
    tb.dut._log.info("SYSTEM WILL GO TO RUNNING STATE: normal_start_up_with_no_log")

    # Initialize and reset
    await tb.reset()

    # Enable the system
    dut.sys_en.value = 1

    # Wait for START_DMA state
    await tb.wait_for_state(5, None, True, tb.SHUTDOWN_FORCE_DELAY + tb.SHUTDOWN_RESET_DELAY + tb.SHUTDOWN_RESET_PULSE + 5)
    # Simulate DAC buffer loading
    dut.dac_buf_loaded.value = 1  # Set dac_buf_full to 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # Simulate SPI running
    dut.spi_running.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # Now should be in RUNNING state
    # wait one cycle for interrupt to be cleared
    state = int(dut.state.value)
    assert state == 7, f"Expected state 7, got {state}"
    await RisingEdge(dut.clk)
    assert dut.ps_interrupt.value == 0, "Interrupt should be cleared"
    tb.dut._log.info("now in RUNNING state")
    return tb


# At the IDLE state if there is an error in the configuration, the system should go to HALTED state.
@cocotb.test()
async def test_configuration_errors(dut):
    tb = await setup_testbench(dut)

    
    tb.dut._log.info("STARTING TEST: test_configuration_errors")

    # Error conditions to test for
    error_conditions = [
        (dut.trig_lockout_oob, 3, "STATUS_TRIG_LOCKOUT_OOB"),
        (dut.cal_offset_oob, 4, "STATUS_CAL_OFFSET_OOB"),
        (dut.dac_divider_oob, 5, "STATUS_DAC_DIVIDER_OOB"),
        (dut.integ_thresh_avg_oob, 6, "STATUS_INTEG_THRESH_AVG_OOB"),
        (dut.integ_window_oob, 7, "STATUS_INTEG_WINDOW_OOB"),
        (dut.integ_en_oob, 8, "STATUS_INTEG_EN_OOB"),
        (dut.sys_en_oob, 9, "STATUS_SYS_EN_OOB")
    ]

    # Iterate through each error condition
    for error_signal, expected_status, status_name in error_conditions:
        await tb.reset()
        tb.dut._log.info(f"Testing error condition: {status_name}")

        error_signal.value = 1  # Set the error signal to 1
        dut.sys_en.value = 1  # Enable the system
        tb.dut._log.info(f"sys_en = {dut.sys_en.value}, {status_name} = {error_signal.value}")
        await tb.check_state_and_status(1, 1)  # IDLE = 1, STATUS_OK = 1

        await tb.wait_for_state(8) # HALTED = 8
        tb.dut._log.info(f"sys_en = {dut.sys_en.value}, {status_name} = {error_signal.value}")
        await tb.check_state_and_status(8, expected_status)  # Check that we are in HALTED = 8 state with the expected status

        error_signal.value = 0 # Reset the error signal
        dut.sys_en.value = 0  # Reset the sys_en signal

# In a normal startup, the system should go from IDLE to RUNNING state. This test checks the state transtions for that.
@cocotb.test()
async def test_normal_startup(dut):
    tb = await setup_testbench(dut)
    tb.dut._log.info("STARTING TEST: test_normal_startup")

    # Initialize and reset
    await tb.reset()
    
    # Verify we start in IDLE state
    await tb.check_state_and_status(1, 1)  # IDLE = 1, STATUS_OK = 1
    
    # Enable the system
    dut.sys_en.value = 1
    
    # Wait for RELEASE_SD_F state
    await tb.wait_for_state(2)  # RELEASE_SD_F = 2
    await tb.check_state_and_status(2, 1)  # Check that we are in RELEASE_SD_F state
    
    # Wait for PULSE_SD_RST state
    await tb.wait_for_state(3, None, False, tb.SHUTDOWN_FORCE_DELAY + 1000)  # PULSE_SD_RST = 3
    await tb.check_state_and_status(3, 1)  # Check that we are in PULSE_SD_RST state

    # Wait for SD_RST_DELAY state
    await tb.wait_for_state(4, None, False, tb.SHUTDOWN_RESET_PULSE + 1000)  # SD_RST_DELAY = 4
    await tb.check_state_and_status(4, 1)  # Check that we are in SD_RST_DELAY state

    # Wait for START_DMA state
    await tb.wait_for_state(5, None, False, tb.SHUTDOWN_RESET_DELAY + 1000)  # START_DMA = 5
    await tb.check_state_and_status(5, 1)  # Check that we are in START_DMA state
    await tb.wait_cycles(100) # Wait for a few cycles to set dac_buf_loaded
    dut.dac_buf_loaded.value = 1  # Set dac_buf_full to 1
    
    # Wait for START_SPI state
    await tb.wait_for_state(6, None, False, tb.BUF_LOAD_WAIT + 1000)  # START_SPI = 6
    await tb.check_state_and_status(6, 1)  # Check that we are in START_SPI state
    await tb.wait_cycles(100)  # Wait for a few cycles to set spi_running
    dut.spi_running.value = 1  # Set spi_running to 1

    # Should reach RUNNING state
    await tb.wait_for_state(7, None, False, tb.SPI_START_WAIT + 1000)  # RUNNING = 7

    # Check that system is properly enabled
    assert dut.sys_rst.value == 0, "System reset should be deasserted"
    assert dut.n_shutdown_force.value == 1, "Shutdown force should be released"
    assert dut.n_shutdown_rst.value == 1, "Shutdown reset should be released"
    assert dut.dma_en.value == 1, "DMA should be enabled"
    assert dut.spi_en.value == 1, "SPI should be enabled"
    assert dut.trig_en.value == 1, "Trigger should be enabled"
    assert dut.ps_interrupt.value == 1, "Interrupt should be asserted"
    
    await RisingEdge(dut.clk)
    assert dut.ps_interrupt.value == 0, "Interrupt should be cleared"

    # Verify we're in RUNNING state with STATUS_OK
    await tb.check_state_and_status(7, 1)  # RUNNING = 7, STATUS_OK = 1

# When in HALTED state, the system should be able to go back to IDLE state when sys_en goes low
@cocotb.test()
async def test_halted_to_idle(dut):
    tb = await normal_start_up_with_no_log(dut)
    tb.dut._log.info("STARTING TEST: test_halted_to_idle")

    # Simulate a runtime error
    dut.lock_viol.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # Check that the system is in HALTED state
    await tb.check_state_and_status(8, 10)  # HALTED = 8, STATUS_LOCK_VIOL = 10
    assert dut.sys_rst.value == 1, "Expected system reset"
    assert dut.n_shutdown_force.value == 0, "Expected shutdown force"
    assert dut.dma_en.value == 0, "Expected DMA disabled"
    assert dut.spi_en.value == 0, "Expected SPI disabled"
    assert dut.ps_interrupt.value == 1, "Expected interrupt asserted"

    dut.sys_en.value = 0  # Enable signal goes low
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await tb.check_state_and_status(1, 1)  # IDLE = 1, STATUS_OK = 1
    assert dut.unlock_cfg.value == 1, "Expected unlock_cfg to be 1"
    


# Test runtime errors in RUNNING state, system should go to HALTED state
@cocotb.test()
async def test_runtime_errors(dut):

    error_conditions = [
        (dut.lock_viol, 10, "STATUS_LOCK_VIOL"),
        (dut.shutdown_sense, 11, "STATUS_SHUTDOWN_SENSE"),
        (dut.ext_shutdown, 12, "STATUS_EXT_SHUTDOWN"),
        (dut.dac_over_thresh, 13, "STATUS_DAC_OVER_THRESH"),
        (dut.adc_over_thresh, 14, "STATUS_ADC_OVER_THRESH"),
        (dut.dac_thresh_underflow, 15, "STATUS_DAC_THRESH_UNDERFLOW"),
        (dut.dac_thresh_overflow, 16, "STATUS_DAC_THRESH_OVERFLOW"),
        (dut.adc_thresh_underflow, 17, "STATUS_ADC_THRESH_UNDERFLOW"),
        (dut.adc_thresh_overflow, 18, "STATUS_ADC_THRESH_OVERFLOW"),
        (dut.dac_buf_underflow, 19, "STATUS_DAC_BUF_UNDERFLOW"),
        (dut.dac_buf_overflow, 20, "STATUS_DAC_BUF_OVERFLOW"),
        (dut.adc_buf_underflow, 21, "STATUS_ADC_BUF_UNDERFLOW"),
        (dut.adc_buf_overflow, 22, "STATUS_ADC_BUF_OVERFLOW"),
        (dut.premat_dac_trig, 23, "STATUS_PREMAT_DAC_TRIG"),
        (dut.premat_adc_trig, 24, "STATUS_PREMAT_ADC_TRIG"),
        (dut.premat_dac_div, 25, "STATUS_PREMAT_DAC_DIV"),
        (dut.premat_adc_div, 26, "STATUS_PREMAT_ADC_DIV")
    ]

    for error_signal, expected_status, status_name in error_conditions:
        tb = await normal_start_up_with_no_log(dut)
        tb.dut._log.info(f"Testing error condition: {status_name}")

        # Set the error signal to 1
        error_signal.value = 1
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)

        # Check that we are in HALTED state
        await tb.check_state_and_status(8, expected_status)

        assert dut.sys_rst.value == 1, "Expected system reset"
        assert dut.n_shutdown_force.value == 0, "Expected shutdown force"
        assert dut.dma_en.value == 0, "Expected DMA disabled"
        assert dut.spi_en.value == 0, "Expected SPI disabled"
        assert dut.ps_interrupt.value == 1, "Expected interrupt asserted"


# Test runtime errors race conditions in RUNNING state, to see which error is picked up first
@cocotb.test(skip=True)
async def test_runtime_error_race_condition(dut):
    tb = await normal_start_up_with_no_log(dut)
    tb.dut._log.info("STARTING TEST: test_runtime_error_race_condition")

    # An error signal
    await Timer(tb.clk_period / 4, units=tb.time_unit)
    dut.dac_buf_underflow.value = 0x08 # Board 3

    # Another error signal slightly later but within the same clock cycle
    await Timer(tb.clk_period / 4, units=tb.time_unit)
    dut.adc_buf_overflow.value = 0x04 # Board 2

    # Another error signal
    await Timer(tb.clk_period / 4, units=tb.time_unit)
    dut.premat_dac_trig.value = 0x02 # Board 1

    # Let the system process the error signals
    await tb.wait_cycles(2)

    # Check that the system is in HALTED state
    await tb.check_state(8)
    status_info = tb.extract_state_and_status()
    tb.dut._log.info(f"State name: {status_info['state_name']}")
    tb.dut._log.info(f"Status name: {status_info['status_name']}")
    tb.dut._log.info(f"Board number: {status_info['board_num']}")
    # TO DO


# Test dac buffer fill timeout, the system should go to HALTED state
@cocotb.test()
async def test_dac_buffer_fill_timeout(dut):
    tb = await setup_testbench(dut)
    tb.dut._log.info("STARTING TEST: test_dac_buffer_fill_timeout")


    # Initialize and reset
    await tb.reset()

    # Enable the system
    dut.sys_en.value = 1
    dut.dac_buf_loaded.value = 0

    # Wait for START_DMA state
    await tb.wait_for_state(5, None, True, tb.SHUTDOWN_FORCE_DELAY + tb.SHUTDOWN_RESET_DELAY + tb.SHUTDOWN_RESET_PULSE + 5)

    # Simulate DAC buffer timeout
    tb.dut._log.info(f"BUF LOAD WAIT parameter is {dut.BUF_LOAD_WAIT.value}")
    tb.dut._log.info(f"Simulating DAC buffer timeout, waiting for {tb.BUF_LOAD_WAIT + 1} cycles")
    await tb.wait_cycles(tb.BUF_LOAD_WAIT + 1)

    if(int(dut.timer.value) > tb.BUF_LOAD_WAIT):
        tb.dut._log.info(f"timer value is {int(dut.timer.value)}, maximum wait time was {tb.BUF_LOAD_WAIT}")

    await tb.check_state_and_status(8, 27)  # HALTED = 8, STATUS_DAC_BUF_FILL_TIMEOUT = 27
    assert dut.sys_rst.value == 1, "Expected system reset"
    assert dut.n_shutdown_force.value == 0, "Expected shutdown force"
    assert dut.dma_en.value == 0, "Expected DMA disabled"
    assert dut.ps_interrupt.value == 1, "Expected interrupt asserted"

# Test SPI timeout, the system should go to HALTED state
@cocotb.test()
async def test_spi_timeout(dut):
    tb = await setup_testbench(dut)
    tb.dut._log.info("STARTING TEST: test_spi_timeout")

    # Initialize and reset
    await tb.reset()

    # Enable the system
    dut.sys_en.value = 1
    dut.spi_running.value = 0

    # Wait for START_DMA state
    await tb.wait_for_state(5, None, True, tb.SHUTDOWN_FORCE_DELAY + tb.SHUTDOWN_RESET_DELAY + tb.SHUTDOWN_RESET_PULSE + 5)

    # Simulate DAC buffer loading
    dut.dac_buf_loaded.value = 1  # Set dac_buf_full to 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # Simulate SPI timeout
    tb.dut._log.info(f"SPI START WAIT parameter is {dut.SPI_START_WAIT.value}")
    tb.dut._log.info(f"Simulating SPI timeout, waiting for {tb.SPI_START_WAIT + 1} cycles")
    await tb.wait_cycles(tb.SPI_START_WAIT + 1)

    if(int(dut.timer.value) > tb.SPI_START_WAIT):
        tb.dut._log.info(f"timer value is {int(dut.timer.value)}, maximum wait time was {tb.SPI_START_WAIT}")

    await tb.check_state_and_status(8, 28) # HALTED = 8, STATUS_SPI_TIMEOUT = 28
    assert dut.sys_rst.value == 1, "Expected system reset"
    assert dut.n_shutdown_force.value == 0, "Expected shutdown force"
    assert dut.dma_en.value == 0, "Expected DMA disabled"
    assert dut.spi_en.value == 0, "Expected SPI disabled"
    assert dut.ps_interrupt.value == 1, "Expected interrupt asserted"

# Test to see if extract board number function works correctly
# The board number is extracted from the DAC over threshold bits
# The board number is the position of the first bit set to 1
# The function should be able to extract the board number from the DAC over threshold bits
@cocotb.test()
async def test_extract_board_number(dut):
    tb = await normal_start_up_with_no_log(dut)
    tb.dut._log.info("STARTING TEST: test_extract_board_number")

    # Test each bit position 
    for i in range(8):
        dut.dac_over_thresh.value = 1 << i
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)

        await tb.check_state(8)
        tb.dut._log.info(f"Checking board number {i}, got {int(dut.board_num.value)}")
        assert dut.board_num.value == i, f"Expected board number {i}, got {int(dut.board_num.value)}"

        await normal_start_up_with_no_log(dut)
    
# Test to see if extract board number function works correctly when multiple DACs are over threshold for instance
# The board number extracted would be the lowest bit set to 1
@cocotb.test()
async def test_extract_board_num_multiple_bits(dut):
    tb = await normal_start_up_with_no_log(dut)
    tb.dut._log.info("STARTING TEST: test_extract_board_num_multiple_bits")

    # Test multiple bits set
    dut.dac_over_thresh.value = 0b00110101
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    await tb.check_state(8)
    assert dut.board_num.value == 0, f"Board number should be 0 (lowest bit), got {dut.board_num.value}"

# Test to see the response of the system with reset pulses of varying widths
@cocotb.test()
async def test_async_reset_behaviour(dut):
    # Go to RUNNING state
    tb = await normal_start_up_with_no_log(dut)
    tb.dut._log.info("STARTING TEST: test_async_reset_behaviour")

    # Test with a short reset pulse during RUNNING state
    await Timer(tb.clk_period / 4, units=tb.time_unit)
    dut.rst.value = 1
    await Timer(tb.clk_period / 4, units=tb.time_unit)
    tb.dut._log.info(f"Short reset pulse, reset value: {dut.rst.value}")
    dut.sys_en.value = 0
    dut.rst.value = 0
    await tb.wait_cycles(10)

    # Verify that the system put us back to IDLE state with proper initialization
    await tb.check_state_and_status(1, 1) # IDLE = 1
    assert dut.sys_rst.value == 1, "Expected system reset"
    assert dut.n_shutdown_force.value == 0, "Expected shutdown force"
    assert dut.unlock_cfg.value == 1, "Expected unlock_cfg to be 1"

    # Test reset during state transition
    await normal_start_up_with_no_log(dut)

    # Apply reset exactly at the same time with a condition that would cause a state transition
    dut.ext_shutdown.value = 1
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    tb.dut._log.info(f"Reset during state transition, reset value: {dut.rst.value}. Ext shutdown value: {dut.ext_shutdown.value}")
    dut.rst.value = 0
    dut.sys_en.value = 0
    await tb.wait_cycles(10)

    # Verify that the system put us back to IDLE state with proper initialization
    await tb.check_state_and_status(1, 1) # IDLE = 1
    assert dut.sys_rst.value == 1, "Expected system reset"
    assert dut.n_shutdown_force.value == 0, "Expected shutdown force"
    assert dut.unlock_cfg.value == 1, "Expected unlock_cfg to be 1"

    
