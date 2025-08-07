**Updated 2025-07-29**
# AD5676 DAC Control Core


The `shim_ad5676_dac_ctrl` module controls the AD5676 DAC in the Rev D shim firmware via a command buffer. It manages SPI communication, command sequencing, calibration, error handling, and synchronization for the 8 DAC channels on the AD5676.

## Inputs and Outputs

### Inputs

- `clk`, `resetn`: Main clock and active-low reset.
- `cmd_word [31:0]`: Command word from buffer.
- `cmd_buf_empty`: Indicates if command buffer is empty.
- `trigger`: External trigger signal.
- `ldac_shared`: Shared LDAC signal (for error detection).
- `miso_sck`, `miso_resetn`, `miso`: SPI MISO clock, reset, and data.

### Outputs

- `setup_done`: Indicates successful boot and setup.
- `cmd_word_rd_en`: Enables reading the next command word.
- `waiting_for_trig`: Indicates waiting for trigger.
- `boot_fail`, `cmd_buf_underflow`, `unexp_trig`, `bad_cmd`, `cal_oob`, `dac_val_oob`: Error flags.
- `abs_dac_val_concat [119:0]`: Concatenated absolute DAC values.
- `n_cs`: SPI chip select (active low).
- `mosi`: SPI MOSI data.
- `ldac`: LDAC output for DAC update.

## Operation

### Command Types

- **NO_OP (`2'b00`):** Take no actions. Used for just a delay or trigger wait.
- **DAC_WR (`2'b01`):** Write DAC values.
- **SET_CAL (`2'b10`):** Set calibration value for a channel.
- **CANCEL (`2'b11`):** Cancel current wait or delay.

### Command Word Structure

`[31:30]` - Command code (2 bits).

#### NO_OP Command (`2'b00`)
- `[29]` - TRIGGER WAIT: If set, waits at the end of the command for an external trigger. Otherwise, waits until delay timer expires.
- `[28]` - CONTINUE: If set, expects the next command to be immediately available after the current command completes (trigger or delay).
- `[27]` - LDAC: If set, pulses LDAC at the end of the command.
- `[26]` - Unused.
- `[25:0]` - Delay timer: Used for delay timer (in clock cycles) if TRIGGER WAIT is not set.

This command will not perform SPI actions. It will wait for the specified delay or trigger, and if LDAC is set, it will pulse LDAC at the end of the command. Otherwise, it can be used for a delay or trigger sycnhronization block.

#### DAC_WR Command (`2'b01`)
- `[29]` - TRIGGER WAIT: If set, waits at the end of the command for an external trigger. Otherwise, waits until delay timer expires.
- `[28]` - CONTINUE: If set, expects the next command to be immediately available after the current command completes (trigger or delay).
- `[27]` - LDAC: If set, pulses LDAC at the end of the command.
- `[26]` - Unused.
- `[25:0]` - Delay timer: Used for delay timer (in clock cycles) if TRIGGER WAIT is not set.

After the command is processed, the core expects 4 incoming 32-bit words, each containing the DAC values for a pair of channels. The incoming words are packed as follows:
- `[15:0]` - First channel value
- `[31:16]` - Second channel value

The words are processed in pairs, with each word corresponding to two channels:

- Word 1: Channels 0 and 1
- Word 2: Channels 2 and 3
- Word 3: Channels 4 and 5
- Word 4: Channels 6 and 7

The command will end following a delay or trigger AFTER processing all 4 words, and the core will pulse LDAC if the LDAC flag is set when the command completes.

#### SET_CAL Command (`2'b10`)
- `[29:19]` - Unused
- `[18:16]` - Channel index (0-7)
- `[15:0]`  - Signed calibration value for the specified channel (range: -32768 to 32767, capped by `ABS_CAL_MAX` parameter).

This command sets the calibration value for a specific channel. The calibration value is applied to the DAC value when loaded in from the command buffer. If the calibration value is out of bounds relative to the `ABS_CAL_MAX` parameter, the `cal_oob` error flag is set. If the addition of the calibration value to the DAC value results in an out-of-bounds value, the `dac_val_oob` error flag is set.

#### CANCEL Command (`2'b11`)
- `[29:0]` - Unused

If the current state is waiting for a trigger or delay, if the next command is a CANCEL command, the core will immediately exit the wait state and return to IDLE. From the user side, it's recommended to clear the command buffer before issuing a CANCEL command in order to cancel immediately, as the core will only cancel once the CANCEL command is at the end of the buffer.

### State Machine

- **RESET:** Initialization.
- **INIT/TEST_WR/REQ_RD/TEST_RD:** Boot-time test and verification.
- **IDLE:** Awaiting commands.
- **DELAY/TRIG_WAIT:** Wait for delay or trigger.
- **DAC_WR:** Perform DAC update.
- **ERROR:** Halt on error.

### Calibration

- Per-channel signed calibration, bounded by `ABS_CAL_MAX`.
- Calibration values are applied to DAC updates.

### Error Handling

- Boot readback mismatch.
- Unexpected triggers or LDAC assertion.
- Invalid commands.
- Buffer underflow.
- Out-of-bounds calibration or DAC values.

## Notes

- SPI timing and chip select are managed to meet AD5676 requirements.
- All conversions between offset and signed values are handled internally.
- Uses asynchronous FIFO and synchronizer modules for safe cross-domain data transfer.

## References

- [AD5676 Datasheet](https://www.analog.com/en/products/ad5676.html)
- [7 Series Memory Resources](https://docs.amd.com/v/u/en-US/ug473_7Series_Memory_Resources)

---
*See the source code for detailed implementation and signal descriptions.*
