# Example 06: UART

This example adds no userspace programs -- it enables the PS `UART1` controller, which shows up in Linux as `/dev/ttyPS1`. Check it from the main console:

```sh
ls -l /dev/ttyPS*          # /dev/ttyPS0 (console) and /dev/ttyPS1 should both exist
stty -F /dev/ttyPS1 115200 # set a baud rate
echo hello > /dev/ttyPS1   # should appear on a 3.3 V UART adapter wired to MIO 36/37
```

Seeing `/dev/ttyPS1` confirms the PS peripheral configuration made it from `block_design.tcl` all the way to the running kernel.
