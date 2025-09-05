**Updated 2025-09-02**
# AD5676 DAC Control Core

The `shim_ad5676_dac_ctrl` module implements command-driven control for the Analog Devices AD5676 DAC in the Rev D shim firmware. It manages SPI transactions, command sequencing, per-channel calibration, error detection, and synchronization for all 8 DAC channels.

## Supported Device

- AD5676 (16-bit, 8-channel DAC)

## Inputs and Outputs

### Inputs

- `clk`, `resetn`: Main clock and active-low reset.
- `boot_test_skip`: Skips boot-time SPI register test if asserted.
- `debug`: Enables debug mode (debug outputs to the data buffer).
- `n_cs_high_time [4:0]`: Chip select high time in clock cycles (max 31), latched when exiting reset.
- `cmd_word [31:0]`: Command word from buffer.
- `cmd_buf_empty`: Indicates command buffer is empty.
- `trigger`: External trigger signal.
- `ldac_shared`: Shared LDAC signal (for error detection).
- `miso_sck`, `miso_resetn`, `miso`: SPI MISO clock, reset, and data.
- `data_buf_full`: Indicates data buffer is full.

### Outputs

- `setup_done`: Indicates successful boot/setup (set immediately if `boot_test_skip` is asserted).
- `cmd_word_rd_en`: Enables reading the next command word.
- `waiting_for_trig`: Indicates waiting for trigger.
- `data_word_wr_en`: Enables writing a data word to the output buffer.
- `data_word [31:0]`: Packed debug or readback data.
- Error flags: `boot_fail`, `cmd_buf_underflow`, `data_buf_overflow`, `unexp_trig`, `bad_cmd`, `cal_oob`, `dac_val_oob`.
- `abs_dac_val_concat [119:0]`: Concatenated absolute DAC values (8 × 15 bits).
- `n_cs`: SPI chip select (active low).
- `mosi`: SPI MOSI data.
- `ldac`: LDAC output for DAC update.

## State Machine

The state machine in `shim_ad5676_dac_ctrl` uses the following codes:

| State Code | Name         | Description                                                                 |
|:----------:|:-------------|:----------------------------------------------------------------------------|
| `0`        | `S_RESET`    | Reset state; waits for `resetn` deassertion.                                |
| `1`        | `S_INIT`     | Initialization; starts SPI register write for boot test.                    |
| `2`        | `S_TEST_WR`  | Boot test: writes test value to DAC register.                               |
| `3`        | `S_REQ_RD`   | Boot test: requests readback of test value.                                 |
| `4`        | `S_TEST_RD`  | Boot test: reads back register value and checks for match.                  |
| `5`        | `S_IDLE`     | Idle; waits for new command from buffer.                                    |
| `6`        | `S_DELAY`    | Delay timer; waits for specified cycles before next command.                |
| `7`        | `S_TRIG_WAIT`| Waits for external trigger signal.                                          |
| `8`        | `S_DAC_WR`   | Performs DAC write sequence for all channels.                               |
| `9`        | `S_DAC_WR_CH`| Immediately and simply write to a single DAC channel.                       |
| `15`       | `S_ERROR`    | Error state; indicates boot/readback failure or invalid command/condition.  |

State transitions are managed based on command type, trigger, delay, and error conditions.

### Boot Test

If `boot_test_skip` is asserted, boot-time SPI register test is skipped and `setup_done` is set immediately. The core will go from `S_RESET` to `S_IDLE` directly.

Otherwise, the core performs a boot test by writing a known value to a DAC channel and reading it back to verify correct operation. If the readback does not match the expected value, the core transitions to `S_ERROR`.

The boot test sequence is as follows:
1. `S_RESET -> S_INIT`: After exiting reset, the core prepares to write a test value to DAC channel 5.

2. `S_INIT -> S_TEST_WR`: Writes the test value (`DAC_TEST_VAL`) to channel 5.
  - SPI command composition:
    - `[23:20]` = `0001` (SPI register write command)
    - `[19]`    = `0` (reserved)
    - `[18:16]` = `101` (channel 5)
    - `[15:0]`  = `DAC_TEST_VAL` (`1000000000001010`, `0x800A`)
  - SPI word written:
    ```
    0001_0_101_1000000000001010
    0x15800A
    ```

3. `S_TEST_WR -> S_REQ_RD`: After write completion, requests readback of channel 5.
  - SPI command composition:
    - `[23:20]` = `1001` (SPI register read command)
    - `[19]`    = `0` (reserved)
    - `[18:16]` = `101` (channel 5)
    - `[15:0]`  = `0000000000000000`, `0x0000`
  - SPI word written:
    ```
    1001_0_101_0000000000000000
    0x950000
    ```

4. `S_REQ_RD -> S_TEST_RD`: After read request completion, reads back the register value while also resetting it.
  - SPI command composition:
    - `[23:20]` = `0001` (SPI register write command)
    - `[19]`    = `0` (reserved)
    - `[18:16]` = `101` (channel 5)
    - `[15:0]`  = `DAC_MIDRANGE` (`0111111111111111`, `0x7FFF`)
  - SPI word written:
    ```
    0001_0_101_0111111111111111
    0x14A7FFF
    ```
  - SPI response composition:
    - `[23:16]` = Undefined (not used)
    - `[15:0]` = Readback value (should match `DAC_TEST_VAL`)
  - SPI response expected (MISO):
    ```
    XXXXXXX_1000000000001010
    0xXX800A
    ```

5. `S_TEST_RD -> S_IDLE`: If readback matches expected value, setup is complete (set `setup_done`); otherwise, transitions to `S_ERROR` and sets `boot_fail`.

## Operation

The core operates based on 32-bit word commands read from the command buffer. These are read sequentially, and the core executes each command fully before reading the next (excepting the CANCEL command).

### Command Types

- **NO_OP (`3'd0`):** Delay or trigger wait, optional LDAC pulse.
- **SET_CAL (`3'd1`):** Set calibration value for a channel.
- **DAC_WR (`3'd2`):** Write DAC values (4 words, 2 channels each).
- **DAC_WR_CH (`3'd3`):** Write single DAC channel.
- **CANCEL (`3'd7`):** Cancel current wait or delay.

### Command Word Structure

- `[31:29]` — **Command Code** (3 bits).

#### NO_OP (`3'd0`)
- `[28]` — **TRIGGER WAIT**: If set, waits for external trigger (`trigger` input); otherwise, uses value as delay timer.
- `[27]` — **CONTINUE**: If set, expects next command immediately after current completes; if not, returns to IDLE unless buffer underflow.
- `[26]` — **LDAC**: If set, pulses `ldac` output at end of command.
- `[24:0]` — **Value**: If TRIGGER WAIT is set, this is the trigger counter (number of triggers to wait for); otherwise, it is the delay timer (number of clock cycles to wait, zero is allowed).

This command does not update DAC values, but can pulse LDAC if requested. If TRIGGER WAIT is set, the core waits for the specified number of external trigger events. Otherwise, it waits for the delay timer to expire.

Note that the trigger counter represents the exact number of triggers to wait for, so a value of 0 means finish immediately (no triggers), and a value of 1 means wait for one trigger.

**State transitions:**
- `S_IDLE -> S_TRIG_WAIT/S_DELAY -> S_IDLE/S_ERROR/next_cmd_state`
- Transition to the next command state if one is present. Otherwise, go to `S_ERROR` if CONTINUE is set, or return to `S_IDLE` if not.

#### SET_CAL (`3'd1`)
- `[18:16]` — **Channel Index** (0–7)
- `[15:0]`  — **Signed Calibration Value** (range: -`ABS_CAL_MAX` to `ABS_CAL_MAX`)

Sets per-channel signed calibration value. Calibration is applied to DAC updates before conversion to offset format. Out-of-bounds calibration sets the `cal_oob` error flag.

**State transitions:**
- `S_IDLE -> S_IDLE/S_ERROR/next_cmd_state`
- Will set `cal_oob` if the calibration value is out of bounds.
- Transition to the next command state if one is present. Otherwise, return to `S_IDLE`.

#### DAC_WR (`3'd2`)
- `[28]` — **TRIGGER WAIT**
- `[27]` — **CONTINUE**
- `[26]` — **LDAC**
- `[24:0]` — **Value**: If TRIGGER WAIT is set, this is the trigger counter (number of triggers to wait for) after DAC update; otherwise, it is the delay timer (number of clock cycles to wait after DAC update, zero is allowed).

Initiates a DAC update sequence. The core expects 4 subsequent words, each containing two 16-bit DAC values: `[31:16]` for channel N+1, `[15:0]` for channel N. Channels are updated in pairs: (0,1), (2,3), (4,5), (6,7). LDAC is pulsed after all channels are updated if the LDAC flag is set.

After the DAC update, the core either waits for the specified number of triggers or delay cycles, depending on the TRIGGER WAIT flag. The trigger counter represents the exact number of triggers to wait for, so a value of 0 means finish immediately (no triggers), and a value of 1 means wait for one trigger.

**State transitions:**
- `S_IDLE -> S_DAC_WR -> S_TRIG_WAIT/S_DELAY -> S_IDLE/S_ERROR/next_cmd_state`
- Transition to the next command state if one is present. Otherwise, go to `S_ERROR` if CONTINUE is set, or return to `S_IDLE` if not.

#### DAC_WR_CH (`3'd3`)
- `[18:16]` — **Channel Index** (0–7)
- `[15:0]` — **DAC Value**

Writes a single DAC channel with the specified value. Has no delays or trigger waits after completion, and immediately pulses LDAC.

**State transitions:**
- `S_IDLE -> S_DAC_WR_CH -> S_IDLE/next_cmd_state`
- Transition to the next command state if one is present. Otherwise return to `S_IDLE`.

#### CANCEL (`3'd7`)
Cancels current wait or delay if issued while the core is in DELAY or TRIG_WAIT state (or just finishing DAC_WR, about to transition to one of those). This is the only command that can be read without the previous command being finished. After canceling, the core returns to IDLE.

**State transitions:**
- `S_TRIG_WAIT/S_DELAY/S_DAC_WR -> S_IDLE`

## Data Buffer Output

### Debug Mode

If `debug` is asserted, the core outputs debug information in addition to DAC readback. On a given clock cycle, the core will choose what to output in the following priority order:
1. If a MISO data word is read during boot test, output a word using Debug Code 1 (`DBG_MISO_DATA`), including the MISO data.
2. If a state transition occurs, output a word using Debug Code 2 (`DBG_STATE_TRANSITION`), including the previous and current state.
3. If the chip select timer starts, output a word using Debug Code 3 (`DBG_N_CS_TIMER`), including the timer value.
4. If the SPI bit counter changes from 0 to nonzero, output a word using Debug Code 4 (`DBG_SPI_BIT`), including the SPI bit value.

Debug output format:
- `[31:28]` - Debug Code (see below)
- Remaining bits: debug data (varies by code, see below)

| Debug Code | Name                   | Data Format                                 |
|:----------:|:-----------------------|:--------------------------------------------|
| 1          | `DBG_MISO_DATA`        | `[15:0]` MISO data                          |
| 2          | `DBG_STATE_TRANSITION` | `[7:4]` prev_state, `[3:0]` state           |
| 3          | `DBG_N_CS_TIMER`       | `[7:0]` n_cs_timer value                    |
| 4          | `DBG_SPI_BIT`          | `[4:0]` spi_bit value                       |

If none of the above conditions are met, the output word is zero and nothing is written to the data buffer.

## Calibration

- Per-channel signed calibration, bounded by `ABS_CAL_MAX` (default 4096).
- Calibration values are applied to DAC updates before conversion to offset format.
- Out-of-bounds calibration or DAC values set error flags (`cal_oob`, `dac_val_oob`).
- Absolute DAC values for all channels are concatenated in `abs_dac_val_concat`.

## Error Handling

- Boot readback mismatch (`boot_fail`)
- Unexpected trigger or LDAC assertion (`unexp_trig`)
- Invalid commands (`bad_cmd`)
- Buffer underflow (expect next command with command buffer empty) (`cmd_buf_underflow`)
- Buffer overflow (try to write to data buffer with data buffer full) (`data_buf_overflow`)
- Out-of-bounds calibration or DAC values (`cal_oob`, `dac_val_oob`)

## Notes

- SPI timing and chip select are managed to meet AD5676 requirements.
- The `n_cs_high_time` input is latched when the state machine is in `S_RESET` to ensure stable timing parameters throughout operation.
- Offset/signed conversions handled internally (see source for conversion functions).
- Asynchronous FIFO and synchronizer modules are used for safe cross-domain data transfer.
- Data buffer output is for debug and boot test readback; normal DAC operation does not output samples.

## References

- [AD5676 Datasheet](https://www.analog.com/en/products/ad5676.html)
- [7 Series Memory Resources](https://docs.amd.com/v/u/en-US/ug473_7Series_Memory_Resources)
- See also: [ADS816x ADC Control Core](../shim_ads816x_adc_ctrl/README.md) for similar command-driven architecture.

---
*See the source code for detailed implementation and signal descriptions.*
