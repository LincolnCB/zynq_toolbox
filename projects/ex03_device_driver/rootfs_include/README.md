# Example 03: Device Driver

This image ships two versions of the same register test, already built and on your `PATH`. They exercise the same `CFG -> NAND -> STS` hardware as Example 02 -- one through the `pl-reg` driver, one through `/dev/mem` -- so you can compare the two approaches.

## `reg-driver`

Runs the NAND round-trip test through the `pl-reg` device nodes (`/dev/cfg`, `/dev/sts`). Those nodes are world-accessible, so it needs no root:

```sh
reg-driver
```

It prints the round-trip vectors, a benchmark line, and `All checks passed.`

## `reg-mem`

The `/dev/mem` baseline for comparison -- the same test, but through `/dev/mem`, so it needs root:

```sh
sudo reg-mem
```

Running it without `sudo` fails, which is the whole point of the driver approach.
