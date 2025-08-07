**Updated 2025-07-29**
# ADS816x ADC Control Core

The `shim_ads816x_adc_ctrl` module provides command-based control of the ADS816x ADC family (ADS8168, ADS8167, ADS8166) in the Rev D shim firmware. It manages SPI communication, command sequencing, sample ordering, error handling, and synchronization for up to 8 ADC channels.

## Supported Devices

- ADS8168 (8)
- ADS8167 (7)
- ADS8166 (6)

Select device via the `ADS_MODEL_ID` parameter (to 8, 7, or 6).

## Inputs and Outputs

### Inputs

- `clk`, `resetn`: Main clock and active-low reset.
- `cmd_word [31:0]`: Command word from buffer.
- `cmd_buf_empty`: Indicates if command buffer is empty.
- `trigger`: External trigger signal.
- `miso_sck`, `miso_resetn`, `miso`: SPI MISO clock, reset, and data.
- `data_buf_full`: Indicates if data buffer is full.

### Outputs

- `setup_done`: Indicates successful boot and setup.
- `cmd_word_rd_en`: Enables reading the next command word.
- `waiting_for_trig`: Indicates waiting for trigger.
- `data_word_wr_en`: Enables writing a data word to the output buffer.
- `data_word [31:0]`: Packed ADC data (two samples per word).
- `boot_fail`, `cmd_buf_underflow`, `data_buf_overflow`, `unexp_trig`, `bad_cmd`: Error flags.
- `n_cs`: SPI chip select (active low).
- `mosi`: SPI MOSI data.

## Operation

### Command Types

- **NO_OP (`2'b00`):** Used for delay or trigger wait.
- **ADC_RD (`2'b01`):** Read ADC samples.
- **SET_ORD (`2'b10`):** Set sample order for ADC channels.
- **CANCEL (`2'b11`):** Cancel current wait or delay.

### Command Word Structure

`[31:30]` - Command code (2 bits).

#### NO_OP Command (`2'b00`)
- `[29]` - TRIGGER WAIT: If set, waits for external trigger; otherwise, waits for delay timer.
- `[28]` - CONTINUE: If set, expects next command immediately after current completes.
- `[25:0]` - Delay timer: Used for delay timer (in clock cycles) if TRIGGER WAIT is not set.

This command will not perform SPI actions. It will wait for the specified delay or trigger. It can be used for a delay or trigger sycnhronization block.

#### ADC_RD Command (`2'b01`)
- `[29]` - TRIGGER WAIT
- `[28]` - CONTINUE
- `[25:0]` - Delay timer: Used for delay timer if TRIGGER WAIT is not set.

This command will initiate an ADC read operation, reading 8 channels in the order set by the `SET_ORD` command. The output will be as 4 32-bit words in the data buffer, each containing two ADC samples packed as follows:
- `[15:0]` - First channel value
- `[31:16]` - Second channel value

The words are processed in pairs, with each word corresponding to two channels:
- Word 1: Channels number 0 and 1 in the sequence order
- Word 2: Channels number 2 and 3 in the sequence order
- Word 3: Channels number 4 and 5 in the sequence order
- Word 4: Channels number 6 and 7 in the sequence order

#### SET_ORD Command (`2'b10`)
- `[31:24]` - Unused.
- `[23:21]` - 3-bit channel index for channel 7 of the sample order sequence.
- `[20:18]` - 3-bit channel index for channel 6 of the sample order sequence.
- `[17:15]` - 3-bit channel index for channel 5 of the sample order sequence.
- `[14:12]` - 3-bit channel index for channel 4 of the sample order sequence.
- `[11:9]` - 3-bit channel index for channel 3 of the sample order sequence.
- `[8:6]` - 3-bit channel index for channel 2 of the sample order sequence.
- `[5:3]` - 3-bit channel index for channel 1 of the sample order sequence.
- `[2:0]` - 3-bit channel index for channel 0 of the sample order sequence.

Sets the order in which ADC channels are sampled during ADC_RD commands.

#### CANCEL Command (`2'b11`)
- `[29:0]` - Unused.

If the current state is waiting for a trigger or delay, if the next command is a CANCEL command, the core will immediately exit the wait state and return to IDLE. From the user side, it's recommended to clear the command buffer before issuing a CANCEL command in order to cancel immediately, as the core will only cancel once the CANCEL command is at the end of the buffer.

### State Machine

- **RESET:** Initialization.
- **INIT/TEST_WR/REQ_RD/TEST_RD:** Boot-time test and verification.
- **IDLE:** Awaiting commands.
- **DELAY/TRIG_WAIT:** Wait for delay or trigger.
- **ADC_RD:** Perform ADC sampling.
- **ERROR:** Halt on error.

### Sample Ordering

- Per-channel sample order is configurable via SET_ORD command.
- Default order is 0,1,2,3,4,5,6,7.

### Error Handling

- Boot readback mismatch.
- Unexpected triggers.
- Invalid commands.
- Buffer underflow/overflow.

## Notes

- SPI timing and chip select are managed to meet ADS816x requirements.
- Uses asynchronous FIFO and synchronizer modules for safe cross-domain data transfer.
- Data buffer output is packed as two samples per 32-bit word.

## References

- [ADS8168 Datasheet](https://www.ti.com/product/ADS8168)
- [ADS8167 Datasheet](https://www.ti.com/product/ADS8167)
- [ADS8166 Datasheet](https://www.ti.com/product/ADS8166)

---
*See the source code for detailed implementation and signal descriptions.*
