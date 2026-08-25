# Example 04: Interrupts

This image ships one userspace program, already built and on your `PATH`. It drives and catches the PL-to-PS interrupts through the `pl-reg` and `pl-irq` device nodes, so it needs no root.

## `interrupt-test`

Raises PL interrupt lines and catches them from userspace. On startup it runs a self-test that pulses each of the eight lines and confirms the interrupt reaches userspace, printing a per-line pass/fail result, then drops to a prompt:

```sh
interrupt-test
```

At the prompt, `set <n>` fires one line, `set_all` fires all eight, `status` shows the counts (which should track `/proc/interrupts`), `test` re-runs the self-test, and `exit` quits (`help` lists them).
