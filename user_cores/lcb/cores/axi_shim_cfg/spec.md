# AXI Shim Config Core

- On reset, set each value to a parameterized default value
- Lock the values with an external lock signal -- if the values change after being locked, latch into an error state and send an error signal
- Make sure each value is within a parameterized range (set in localparams to make the hard limits less visible). While outside that range, hold a value-specific "invalid" signal high.
