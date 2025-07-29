import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, ReadWrite
import random
from collections import deque

class shim_spi_cfg_sync_base:

    def __init__(self, dut, clk_period=4, time_unit='ns'):
        self.dut = dut
        self.clk_period = clk_period
        self.time_unit = time_unit

        # Synchronizer Parameters
        # This means any input signal will be stable after 3 * 2 clk cycles if the input remains constant.
        self.SYNC_DEPTH = 3
        self.STABLE_COUNT = 2
        self.STABLE_AFTER_N_CLK_CYCLES = self.SYNC_DEPTH * self.STABLE_COUNT

        # Initialize the clock
        cocotb.start_soon(Clock(dut.spi_clk, clk_period, time_unit).start(start_high=False))

        # Initialize input signals
        self.dut.integ_thresh_avg.value = 0
        self.dut.integ_window.value = 0
        self.dut.integ_en.value = 0
        self.dut.spi_en.value = 0
        self.dut.block_buffers.value = 0

        # Input data queues
        self.integ_thresh_avg_queue = deque(maxlen=self.STABLE_AFTER_N_CLK_CYCLES)
        self.integ_window_queue = deque(maxlen=self.STABLE_AFTER_N_CLK_CYCLES)
        self.integ_en_queue = deque(maxlen=self.STABLE_AFTER_N_CLK_CYCLES)
        self.spi_en_queue = deque(maxlen=self.STABLE_AFTER_N_CLK_CYCLES)
        self.block_buffers_queue = deque(maxlen=self.STABLE_AFTER_N_CLK_CYCLES)

    async def reset(self):
        """Reset the DUT and hold it for two clk cycles."""
        await RisingEdge(self.dut.spi_clk)
        self.dut.sync_resetn.value = 0

        self.dut._log.info("STARTING RESET")
        self.integ_thresh_avg_queue.clear()
        self.integ_window_queue.clear()
        self.integ_en_queue.clear()
        self.spi_en_queue.clear()
        self.block_buffers_queue.clear()

        await RisingEdge(self.dut.spi_clk)
        await RisingEdge(self.dut.spi_clk)
        self.dut.sync_resetn.value = 1
        self.dut._log.info("RESET COMPLETE")

    async def monitor_and_scoreboard(self):
        """Monitor the DUT values and score them against expected values."""

        while True:
            await RisingEdge(self.dut.spi_clk)
            ## Capture the previous values of the DUT here.

            # Previous reset
            prev_sync_resetn = self.dut.sync_resetn.value

            # Previous intermediate values for synchronized signals
            prev_integ_thresh_avg_sync = self.dut.integ_thresh_avg_sync.value
            prev_integ_window_sync = self.dut.integ_window_sync.value
            prev_integ_en_sync = self.dut.integ_en_sync.value
            prev_spi_en_sync = self.dut.spi_en_sync.value
            prev_block_buffers_sync = self.dut.block_buffers_sync.value

            # Previous stability signals
            prev_integ_thresh_avg_stable_flag = self.dut.integ_thresh_avg_stable_flag.value
            prev_integ_window_stable_flag = self.dut.integ_window_stable_flag.value
            prev_integ_en_stable_flag = self.dut.integ_en_stable_flag.value
            prev_spi_en_stable_flag = self.dut.spi_en_stable_flag.value
            prev_block_buffers_stable_flag = self.dut.block_buffers_stable_flag.value

            await ReadOnly()
            ## Work on current values of the DUT here.

            if prev_sync_resetn == 0:
                # If the DUT was reset, all stable flags should be low.
                assert int(self.dut.integ_thresh_avg_stable_flag.value) == 0, "integ_thresh_avg_stable_flag should be low after reset"
                assert int(self.dut.integ_window_stable_flag.value) == 0, "integ_window_stable_flag should be low after reset"
                assert int(self.dut.integ_en_stable_flag.value) == 0, "integ_en_stable_flag should be low after reset"
                assert int(self.dut.spi_en_stable_flag.value) == 0, "spi_en_stable_flag should be low after reset"
                assert int(self.dut.block_buffers_stable_flag.value) == 0, "block_buffers_stable_flag should be low after reset"
            
            elif prev_spi_en_sync == 1 and prev_spi_en_stable_flag == 1:

                # Print the queues for debugging purposes
                self.dut._log.info(f"integ_thresh_avg_queue: {self.integ_thresh_avg_queue}")
                self.dut._log.info(f"integ_window_queue: {self.integ_window_queue}")
                self.dut._log.info(f"integ_en_queue: {self.integ_en_queue}")
                self.dut._log.info(f"spi_en_queue: {self.spi_en_queue}")
                self.dut._log.info(f"block_buffers_queue: {self.block_buffers_queue}")
                
                # Pop the expected values from the queues here.
                integ_thresh_avg_expected = self.integ_thresh_avg_queue.popleft()
                integ_window_expected = self.integ_window_queue.popleft()
                integ_en_expected = self.integ_en_queue.popleft()
                spi_en_expected = self.spi_en_queue.popleft()
                block_buffers_expected = self.block_buffers_queue.popleft()

                if prev_integ_thresh_avg_stable_flag and prev_integ_window_stable_flag and prev_integ_en_stable_flag:
                    # Configuration signals should only be updated when spi_en_sync is high and they're stable.
                    assert int(self.dut.integ_thresh_avg_stable) == prev_integ_thresh_avg_sync == integ_thresh_avg_expected
                    assert int(self.dut.integ_window_stable) == prev_integ_window_sync == integ_window_expected
                    assert int(self.dut.integ_en_stable) == prev_integ_en_sync == integ_en_expected
                    assert int(self.dut.spi_en_stable) == prev_spi_en_sync == spi_en_expected

                if prev_block_buffers_stable_flag == 1:
                    # Block buffers should only be updated when block_buffers_stable_flag is high.
                    assert int(self.dut.block_buffers_stable) == prev_block_buffers_sync == block_buffers_expected

                # Break from the loop if the queues are empty
                if not self.integ_thresh_avg_queue or not self.integ_window_queue or not self.integ_en_queue or not self.spi_en_queue or not self.block_buffers_queue:
                    break

    # NEEDS UPDATE
    async def one_time_driver(self):
        """ Drive random inputs to the DUT, and push them to the queues for monitoring. """
        # Randomly generate inputs
        integ_thresh_avg = random.randint(0, 2**15 - 1)
        integ_window = random.randint(0, 2**32 - 1)
        integ_en = random.randint(0, 1)
        spi_en = 1
        block_buffers = random.randint(0, 1)

        for _ in range(self.STABLE_AFTER_N_CLK_CYCLES):

            await RisingEdge(self.dut.spi_clk)
            # Drive the DUT inputs
            self.dut.integ_thresh_avg.value = integ_thresh_avg
            self.dut.integ_window.value = integ_window
            self.dut.integ_en.value = integ_en
            self.dut.spi_en.value = spi_en
            self.dut.block_buffers.value = block_buffers

            # Push the values to the queues for monitoring
            self.integ_thresh_avg_queue.append(integ_thresh_avg)
            self.integ_window_queue.append(integ_window)
            self.integ_en_queue.append(integ_en)
            self.spi_en_queue.append(spi_en)
            self.block_buffers_queue.append(block_buffers)

