# Example 02: AXI Interface

This image ships two userspace programs, already built and on your `PATH`. Both reach the PL registers through `/dev/mem`, so both need root.

## `reg-test`

Self-checking demonstration of the `CFG -> NAND -> STS` path. It writes operand pairs into the CFG register, reads the NAND result back from STS, and checks it against the expected value:

```sh
sudo reg-test
```

## `mem-test`

Interactive playground for the FIFO and BRAM ports. It maps each port and takes read/write/reset commands so you can push and pop the FIFO and read and write BRAM by hand:

```sh
sudo mem-test
```

Type `help` at the prompt for the command list.
