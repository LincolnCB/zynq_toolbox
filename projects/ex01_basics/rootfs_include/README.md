# Example 01: Basics

This image ships one small userspace program, already built and on your `PATH`.

## `fclk-control`

Interactively reprograms the FPGA fabric clock `FCLK0` while Linux is running. It reaches the System Level Control Registers through `/dev/mem`, so it needs root:

```sh
sudo fclk-control
```

At the prompt, enter a divider number (`0` or `1`) and a value (each `1`-`63`); the resulting clock is `PLL / (div0 * div1)`. For example, `0 7` then `1 2` divides it down. Scope `FCLK0` to watch the frequency change.
