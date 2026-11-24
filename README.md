# Asynchronous (Dual-Clock) FIFO with Gray-Code Pointers — Verilog RTL

A FIFO that safely moves data between two **independent, unrelated clock
domains**, using Gray-coded pointers and 2-flop synchronizers — the standard
(Cummings-paper) technique, and one of the most commonly asked RTL/CDC
interview topics for exactly that reason.

## Why this is a genuinely hard problem, and the two bugs that proved it

A synchronous FIFO is trivial. An asynchronous one is not, because comparing
a write pointer against a read pointer from a *different clock domain* is
inherently unsafe unless done carefully. Two real bugs showed up while
building and simulating this (both are fixed in the current code, and
worth being able to discuss):

1. **A zero-delay combinational loop.** The first version computed the next
   write pointer as `wbin_next = wbin + (wr_en && !full)` and derived `full`
   combinationally from that same `wbin_next` — so `full` depended on itself
   in the same timestep (`full → wbin_next → wgray_next → full`). This isn't
   just a simulator annoyance (it livelocked Icarus Verilog outright); it's
   not realizable in real hardware either, since a combinational loop has no
   well-defined settled value. **Fix:** register `full`/`empty` as flip-flops,
   and gate the pointer increment on the *current, already-registered* full
   flag rather than a same-cycle recomputation of it. This is exactly why
   the Cummings reference design registers these flags instead of leaving
   them combinational — not a style preference.

2. **An off-by-one in the testbench's own read-checking logic**, not the
   RTL. `rd_data` is a registered output, valid starting one `rd_clk` edge
   after a read was issued; the first version of the checker added an
   *extra* one-cycle delay flag on top of that lag, so it ended up comparing
   `rd_data` against the wrong index in the reference model. Tracing it
   through the nonblocking-assignment scheduling by hand (worked out in the
   comments in `tb/tb_async_fifo.v`) showed the fix was simpler than the
   original code: check `rd_en`'s pre-update value at the top of each clock
   edge, before reassigning it — no extra delay register needed at all.

Both are the kind of mistake that's easy to make and a good thing to be able
to walk through: the first is a genuine RTL/CDC hazard, the second is a
reminder that testbenches have their own timing to get right.

## Design

- `rtl/sync_2ff.v` — generic 2-flop synchronizer, parameterized by width (used
  to cross the whole Gray-coded pointer as one bus, not bit-by-bit).
- `rtl/async_fifo.v` — the FIFO itself: Gray-coded write and read pointers
  (one bit wider than the address width so full/empty are distinguishable),
  registered `full`/`empty` flags, dual-port memory array.

```
 wr_clk domain                          rd_clk domain
┌────────────┐     Gray(rd_ptr)       ┌────────────┐
│ wr_ptr_bin │◀── sync_2ff ───────────│ rd_ptr_bin │
│ wr_ptr_gray│                         │ rd_ptr_gray│
│   full     │   Gray(wr_ptr) ───────▶│   empty    │
└────────────┘      sync_2ff          └────────────┘
       │                                      │
       └──────────────▶ mem[] ◀───────────────┘
```

## Verification

`tb/tb_async_fifo.v` runs the two clock domains at deliberately unrelated
periods (7 ns write, 13 ns read — not a clean integer ratio, specifically to
stress the synchronizers rather than let them get lucky) and streams 500
randomized bytes through the FIFO, with the writer backing off on `full` and
the reader backing off on `empty`.

**Result: all 500/500 words crossed intact and in order**, with the FIFO
genuinely observed full 137 times during the run (`docs/sim_log.txt`) —
i.e. this isn't a test that never exercised the interesting corner case.

## Running the simulation

```bash
iverilog -g2005 -o sim.out rtl/sync_2ff.v rtl/async_fifo.v tb/tb_async_fifo.v
vvp sim.out
```

## Status / next steps

- Depth is parametric (`ADDR_WIDTH`), currently 16 entries × 8 bits.
- A natural next step is adding programmable almost-full/almost-empty
  thresholds, which most real designs need for backpressure before the FIFO
  actually fills — and synthesizing it to confirm the dual-port memory maps
  cleanly onto target FPGA block RAM.
