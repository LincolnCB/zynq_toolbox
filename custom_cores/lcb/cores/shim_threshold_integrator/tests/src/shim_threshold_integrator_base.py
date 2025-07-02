import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, ReadWrite
import random
from collections import deque

class shim_threshold_integrator_base:
    
    # State encoding dictionary
    STATES = {
        0: "IDLE",
        1: "SETUP",
        2: "WAIT",
        3: "RUNNING",
        4: "OUT_OF_BOUNDS",
        5: "ERROR"
    }

    def __init__(self, dut, clk_period=4, time_unit="ns"):
        self.dut = dut
        self.clk_period = clk_period
        self.time_unit = time_unit

        # Initialize clock
        cocotb.start_soon(Clock(dut.clk, clk_period, time_unit).start())

        # Initialize input signals
        self.dut.enable.value = 0
        self.dut.window.value = 0
        self.dut.threshold_average.value = 0
        self.dut.sample_core_done.value = 0
        self.dut.abs_sample_concat.value = 0

        # Inputs to drive
        self.driven_window_value = 0
        self.driven_threshold_average_value = 0

        # Channel Queues
        self.TOTAL_FIFO_DEPTH = 1024
        self.channel_queues = [deque() for _ in range(8)]


    def get_state_name(self, state_value):
        """Get the name of the state based on its integer value from STATES dictionary."""
        state_int = int(state_value)
        return self.STATES.get(state_int, f"UNKNOWN_STATE({state_int})")
        
    async def reset(self):
        """Reset the DUT, hold reset for two clk cycles."""
        await RisingEdge(self.dut.clk)
        self.dut.resetn.value = 0
        self.driven_window_value = 0
        self.driven_threshold_average_value = 0

        for q in self.channel_queues:
            q.clear()

        self.dut._log.info("STARTING RESET")
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.resetn.value = 1
        self.dut._log.info("RESET COMPLETE")

    async def state_transition_monitor_and_scoreboard(self):
        """Monitor the state transitions and score them against expected values."""
        previous_state_value = 0
        previous_reset_value = 0
        previous_fifo_full_value = 0
        previous_wr_en_value = 0
        previous_fifo_empty_value = 0
        previous_rd_en_value = 0
        previous_channel_over_thresh_value = 0

        while True:
            await RisingEdge(self.dut.clk)
            previous_reset_value = int(self.dut.resetn.value)
            previous_state_value = int(self.dut.state.value)
            previous_fifo_full_value = int(self.dut.fifo_full.value)
            previous_wr_en_value = int(self.dut.wr_en.value)
            previous_fifo_empty_value = int(self.dut.fifo_empty.value)
            previous_rd_en_value = int(self.dut.rd_en.value)
            previous_channel_over_thresh_value = int(self.dut.channel_over_thresh.value)

            await ReadOnly()

            # reset to IDLE
            if previous_reset_value == 0 and int(self.dut.resetn.value) == 1:
                assert int(self.dut.state.value) == 0,\
                    f"Expected state after reset: 0 (IDLE), got: {int(self.dut.state.value)} ({self.get_state_name(self.dut.state.value)})"

            # IDLE to OUT_OF_BOUNDS
            if previous_state_value == 0 and int(self.dut.over_thresh) == 1:
                assert int(self.dut.state.value) == 4,\
                    f"Expected state after over_thresh in IDLE: 4 (OUT_OF_BOUNDS), got: {int(self.dut.state.value)} ({self.get_state_name(self.dut.state.value)})"
                
                assert int(self.dut.window.value) < 2**11,\
                    f"Expected window value in OUT_OF_BOUNDS: < 2**11, got: {int(self.dut.window.value)}"

            # RUNNING to OUT_OF_BOUNDS
            if bool(previous_channel_over_thresh_value):
                assert int(self.dut.state.value) == 4, \
                    f"Expected state after channel_over_thresh: 4 (OUT_OF_BOUNDS), got: {int(self.dut.state.value)} ({self.get_state_name(self.dut.state.value)})"
                
                assert self.dut.over_thresh.value == 1, \
                    f"Expected over_thresh: 1, got: {int(self.dut.over_thresh.value)}"

            # RUNNING to ERROR
            if (previous_fifo_full_value and previous_wr_en_value):
                assert self.dut.err_overflow.value == 1, \
                    f"Expected err_overflow: 1, got: {int(self.dut.err_overflow.value)}"
                
                assert int(self.dut.state.value) == 5, \
                    f"Expected state after overflow: 5 (ERROR), got: {int(self.dut.state.value)} ({self.get_state_name(self.dut.state.value)})"
                
            if (previous_fifo_empty_value and previous_rd_en_value):
                assert self.dut.err_underflow.value == 1, \
                    f"Expected err_underflow: 1, got: {int(self.dut.err_underflow.value)}"
                
                assert int(self.dut.state.value) == 5, \
                    f"Expected state after underflow: 5 (ERROR), got: {int(self.dut.state.value)} ({self.get_state_name(self.dut.state.value)})"

    async def idle_to_running_state(self):
        """Transition from IDLE to RUNNING state, will leave the DUT at the first cycle of RUNNING state."""

        await RisingEdge(self.dut.clk)
        await ReadWrite()

        # After reset, DUT should be in IDLE state
        assert int(self.dut.state.value) == 0, f"Expected state after reset: 0 (IDLE), got: {int(self.dut.state.value)} ({self.get_state_name(self.dut.state.value)})"

        # Enable the DUT
        self.dut.enable.value = 1 
        
        # Give random value to the window between 2**32-1 and 2**11
        self.driven_window_value = random.randint(2**11, 2**32-1)
        self.dut.window.value = self.driven_window_value

        # Give random value to the threshold_average between 2**15-1 and 0
        self.driven_threshold_average_value = random.randint(0, 2**15-1)
        self.dut.threshold_average.value = self.driven_threshold_average_value

        # DUT should be in SETUP state
        await RisingEdge(self.dut.clk)
        await ReadWrite()

        # Assertions
        assert int(self.dut.window.value) == self.driven_window_value, \
            f"Expected window value: {self.driven_window_value}, got: {int(self.dut.window.value)}"
        
        assert int(self.dut.threshold_average.value) == self.driven_threshold_average_value, \
            f"Expected threshold_average value: {self.driven_threshold_average_value}, got: {int(self.dut.threshold_average.value)}"
        
        self.dut._log.info(f"Window: {self.driven_window_value}")
        self.dut._log.info(f"Threshold Average: {self.driven_threshold_average_value}")
 
        assert int(self.dut.state.value) == 1, \
            f"Expected state after enabling: 1 (SETUP), got: {int(self.dut.state.value)} ({self.get_state_name(self.dut.state.value)})"

        assert int(self.dut.window_reg.value) == int(self.dut.window.value) >> 4, \
            f"Expected window_reg: {int(self.dut.window.value) >> 4}, got: {int(self.dut.window_reg.value)}"

        assert int(self.dut.threshold_average_shift.value) == int(self.dut.threshold_average.value), \
            f"Expected threshold_average_shift: {int(self.dut.threshold_average.value)}, got: {int(self.dut.threshold_average_shift.value)}"

        # Wait for the DUT to transition to WAIT state
        while True:
            await RisingEdge(self.dut.clk)
            await ReadWrite()
            if int(self.dut.state.value) == 2:
                break
        
        # Assertions
        assert int(self.dut.state.value) == 2, \
            f"Expected state after setup: 2 (WAIT), got: {int(self.dut.state.value)} ({self.get_state_name(self.dut.state.value)})"

        assert int(self.dut.max_value.value) == int(self.dut.threshold_average.value) * (int(self.dut.window.value) >> 4), \
            f"Expected max_value: {int(self.dut.threshold_average.value) * (int(self.dut.window.value) >> 4)}, got: {int(self.dut.max_value.value)}"
        
        assert int(self.dut.chunk_size.value) == int(2**self.dut.chunk_width.value-1), \
            f"Expected chunk_size: {2**self.dut.chunk_width.value-1}, got: {int(self.dut.chunk_size.value)}"
        
        # Go to RUNNING state
        await RisingEdge(self.dut.clk)
        self.dut.sample_core_done.value = 1

        # Now in first cycle of RUNNING state
        await RisingEdge(self.dut.clk)
        await ReadWrite()

        # Assertions
        assert int(self.dut.state.value) == 3, \
            f"Expected state after sample_core_done: 3 (RUNNING), got: {int(self.dut.state.value)} ({self.get_state_name(self.dut.state.value)})"
        
        assert int(self.dut.inflow_chunk_timer.value) == int(self.dut.chunk_size.value) << 4, \
            f"Expected inflow_chunk_timer: {int(self.dut.chunk_size.value) << 4}, got: {int(self.dut.inflow_chunk_timer.value)}"
        
        assert int(self.dut.outflow_timer.value) == int(self.dut.window.value) - 1, \
            f"Expected outflow_timer: {int(self.dut.window.value) - 1}, got: {int(self.dut.outflow_timer.value)}"
        
        assert self.dut.setup_done.value == 1, \
            f"Expected setup_done: 1, got: {int(self.dut.setup_done.value)}"
        
        self.dut._log.info("Transitioned to RUNNING state successfully")
        self.dut._log.info(f"Window: {int(self.dut.window.value)}")
        self.dut._log.info(f"Threshold Average: {int(self.dut.threshold_average.value)}")
        self.dut._log.info(f"Chunk Size: {int(self.dut.chunk_size.value)}")
        self.dut._log.info(f"Max Value: {int(self.dut.max_value.value)}")
        self.dut._log.info(f"Initial inflow_chunk_timer: {int(self.dut.inflow_chunk_timer.value)}")
        self.dut._log.info(f"Initial outflow_timer: {int(self.dut.outflow_timer.value)}")



    async def running_state_model_and_scoreboard(self, mode="random_abs_sample_concat_values"):
        """
        Model the RUNNING state and score the DUT against it.
        Expects the DUT to be in the first cycle of RUNNING state otherwise it will work unexpectedly.

        The mode can be: 
        "random_abs_sample_concat_values"
        "max_abs_sample_concat_values"
        "high_abs_sample_concat_values"
        "medium_abs_sample_concat_values"
        "low_abs_sample_concat_values"
        "random_abs_sample_concat_values" (default)

        The default mode is "random_abs_sample_concat_values" which will generate random values for abs_sample_concat.
        max_abs_sample_concat_values mode will drive max 15 bit values for abs_sample_concat.
        high_abs_sample_concat_values mode will drive values above threshold_average.
        medium_abs_sample_concat_values mode will drive values around threshold_average.
        low_abs_sample_concat_values mode will drive values below threshold_average.
        """

        # Starts with the first cycle of RUNNING state
        cycle_count = 1

        # 8 element inflow_value array to hold 15 bit values
        inflow_value = [0] * 8

        # Initialize 120-bit constructed abs_sample_concat value
        constructed_abs_sample_concat = 0

        # Initiliaze previous values for scoreboard
        previous_inflow_chunk_timer_value = int(self.dut.chunk_size.value) << 4
        previous_outflow_timer_value = int(self.dut.window.value) - 1
        previous_inflow_value = [0] * 8

        # Initialize expected values for scoreboard
        expected_inflow_chunk_sum = [0] * 8

        #while True:
        for _ in range(1000):  # Run for a fixed number of cycles for testing
            
            self.dut._log.info(f"CURRENT CYCLE COUNT IN RUNNING STATE: {cycle_count}")
            cycle_count += 1

            # Construct abs_sample_concat values every cycle
            constructed_abs_sample_concat = 0
            for i in range(8):
                if mode == "random_abs_sample_concat_values":
                    random_15_bit_value = random.randint(0, 2**15-1)
                elif mode == "max_abs_sample_concat_values":
                    random_15_bit_value = 2**15 - 1
                elif mode == "high_abs_sample_concat_values":
                    random_15_bit_value = random.randint(int(self.dut.threshold_average.value), 2**15-1)
                elif mode == "medium_abs_sample_concat_values":
                    random_15_bit_value = random.randint(int(self.dut.threshold_average.value) - 1000, int(self.dut.threshold_average.value) + 1000)
                elif mode == "low_abs_sample_concat_values":
                    random_15_bit_value = random.randint(0, int(self.dut.threshold_average.value) - 1)

                inflow_value[i] = random_15_bit_value
                constructed_abs_sample_concat |= random_15_bit_value << (i * 15)

            # Drive the abs_sample_concat value every cycle
            self.dut.abs_sample_concat.value = constructed_abs_sample_concat
            
            # Inflow Logic Scoreboard
            if previous_inflow_chunk_timer_value % 16 == 0:

                self.dut._log.info(f"Previous inflow_chunk_timer: {previous_inflow_chunk_timer_value}")
                self.dut._log.info(f"Current inflow_chunk_timer: {int(self.dut.inflow_chunk_timer.value)}")

                if previous_inflow_chunk_timer_value != 0:
                    # Score the inflow chunk sum
                    for i in range(8):
                        expected_inflow_chunk_sum[i] += previous_inflow_value[i]

                        self.dut._log.info(f"Previous inflow_value[{i}] that should reflect to this cycle: {previous_inflow_value[i]}")
                        self.dut._log.info(f"Expected inflow_chunk_sum[{i}] this cycle: {expected_inflow_chunk_sum[i]}")
                        self.dut._log.info(f"Current inflow_chunk_sum[{i}] this cycle: {int(self.dut.inflow_chunk_sum[i].value)}")

                        # Check if the inflow chunk sum matches the expected value
                        assert int(self.dut.inflow_chunk_sum[i].value) == expected_inflow_chunk_sum[i], \
                            f"Expected inflow_chunk_sum[{i}]: {expected_inflow_chunk_sum[i]}, got: {int(self.dut.inflow_chunk_sum[i].value)}"
                        
                else:
                    for i in range(8):
                        expected_inflow_chunk_sum[i] += previous_inflow_value[i]
                        self.channel_queues[i].append(expected_inflow_chunk_sum[i])

                        self.dut._log.info(f"Previous inflow_value[{i}] that should reflect to this cycle: {previous_inflow_value[i]}")
                        self.dut._log.info(f"Expected queued_fifo_in_chunk_sum[{i}] this cycle: {expected_inflow_chunk_sum[i]}")
                        self.dut._log.info(f"Current queued_fifo_in_chunk_sum[{i}] this cycle: {int(self.dut.queued_fifo_in_chunk_sum[i].value)}")

                        # Check if the inflow chunk sum in FIFO matches the expected value
                        assert int(self.dut.queued_fifo_in_chunk_sum[i].value) == expected_inflow_chunk_sum[i], \
                            f"Expected queued_fifo_in_chunk_sum[{i}]: {expected_inflow_chunk_sum[i]}, got: {int(self.dut.queued_fifo_in_chunk_sum[i].value)}"
                        
                        # Inflow chunk sum should reset to 0
                        expected_inflow_chunk_sum[i] = 0
                        
                        self.dut._log.info(f"Expected inflow_chunk_sum[{i}] this cycle: {expected_inflow_chunk_sum[i]}")
                        self.dut._log.info(f"Current inflow_chunk_sum[{i}] this cycle: {int(self.dut.inflow_chunk_sum[i].value)}")

                        # Check if the inflow_chunk_sum is reset to 0
                        assert int(self.dut.inflow_chunk_sum[i].value) == 0, \
                            f"Expected inflow_chunk_sum[{i}] to be reset to 0, got: {int(self.dut.inflow_chunk_sum[i].value)}"
                    
                    # When previous_inflow_chunk_timer_value is 0, it means we are at the start of a new chunk so:
                    # Inflow chunk timer should be set to chunk_size << 4
                    assert int(self.dut.inflow_chunk_timer.value) == int(self.dut.chunk_size.value) << 4, \
                        f"Expected inflow_chunk_timer: {int(self.dut.chunk_size.value) << 4}, got: {int(self.dut.inflow_chunk_timer.value)}"
                    # FIFO in queue count should be set to 8
                    assert int(self.dut.fifo_in_queue_count.value) == 8, \
                        f"Expected fifo_in_queue_count: 8, got: {int(self.dut.fifo_in_queue_count.value)}"

            await RisingEdge(self.dut.clk)
            previous_inflow_chunk_timer_value = int(self.dut.inflow_chunk_timer.value)
            previous_outflow_timer_value = int(self.dut.outflow_timer.value)
            previous_inflow_value = inflow_value.copy()
            await ReadWrite()

