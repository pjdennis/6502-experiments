# wendy2c PLD bank-aliasing notes

This file documents an attempt — and its limits — to adjust
`22V10-wendy2c.pld` so that `verification_wendy2c.s`'s `test_all`
("memory not overwritten") passes. **The attempt did not succeed; the
test cannot pass with the current 22V10 design.** Notes are kept here
so the next person doesn't have to rediscover the structural reason.

## What `test_all` writes

```
slot   logical addr   cfg            value
1..15  $2000          %00001..%01111  1..15      (15 lower banks)
16     $6000          %00001          16         (lower fixed RAM, unbanked)
17     $A000          %00001          17         (upper bank 1 L)
18..24 $A000          %10001..%10111  18..24     (upper banks 2..8 L)
25     $E000          %00001          25         (upper bank 1 H)
26..32 $E000          %10001..%10111  26..32     (upper banks 2..8 H)
```

32 logical writes total. The check expects every cell to hold its own
value when re-read; any overlap (aliasing) makes the test fail.

## Why the PLD can't separate them

Inside a 32 KiB physical block the offset is `addr & $7FFF`, which is
fixed by the CPU address — the PLD can't change it. Two writes to the
same offset only land in different physical cells if the PLD produces
different `r_bits` values for them.

Group `test_all`'s 32 writes by the physical offset they land on:

| Offset within block | Writes targeting that offset                              | Count |
| ------------------- | --------------------------------------------------------- | ----- |
| `$2000`             | 15 lower banks + 1 upper-L cfg %00001 + 7 upper-L %1000X  | **23** |
| `$6000`             | 1 lower fixed + 1 upper-H cfg %00001 + 7 upper-H %1000X    | 9      |
| `$7FFF`             | (test 2 — separate)                                       | —      |

The PLD outputs four R-bits (R15..R18), so the rest of the address space
above the 32 KiB window is at most **16 distinct physical blocks**. At
offset `$2000` the test asks 23 distinct writes to land in 23 distinct
blocks; pigeonhole says at least **23 − 16 = 7 must alias**. No
re-encoding of R15..R18 can lift this floor.

## The attempt

The PLD comments suggest the intent was for upper-bank-mode (`C4=1`,
`C3=0`) to live at `r_bits` in the range `8..F` (the `Bank $1X000..$1X111`
notation in the source), distinct from lower banks at `1..F`. The
attempted modification (`/tmp/22V10-wendy2c-experimental.pld` in the
session that produced this note) was:

```
R15 += A15 * /A14 * C4 * C2                ; let C2 contribute to R15 in upper-bank mode
R18  = ... + A15 * /A1{4,3,2,1} * C4 * /C3 ; fire R18 always for upper-bank addresses, regardless of C2
```

This shifts the seven forced aliases from `(lower bank 2,4,6,8,10,12,14
↔ upper bank 17..23 L)` to `(lower bank 9..15 ↔ upper bank 17..23 L)` —
arguably "later" in the test sequence, but `test_all`'s check loop
visits lower banks 1..14 in order and prints `N` on the first mismatch,
so it still fails. And the new R18 firing for `$E000` (which test 2
uses) introduces fresh aliases at offset `$7FFF`, breaking test 2 too:

```
Original  PLD: 1Y 2YY 3YY 4YY 5YY / 6NYYYYY F!     (test 6 fails at bank 2; tests 1..5 pass)
Modified  PLD: 1Y 2N  3YY 4YY 5YY / 6NYYYYN F!     (test 2 now fails too)
```

## What it would take to pass

Either more R-output pins (e.g., a different PLD / CPLD with 5+ R-bits
giving 32+ physical blocks), or a different memory architecture where
the 32 logical regions don't all share the same offset within their
blocks (e.g., a paging unit that can map any 8 KiB chunk independently).
With a stock 22V10 and the current address-bit / config-bit allocation,
seven aliases at offset `$2000` are structural.

## Iterating

`emulator/pld_to_c.py` mechanically translates the `.pld` source into
the C header `emulator/chips/clock_22v10_pld_generated.h` that the
emulator's `clock_22v10.c` includes. Edit the `.pld`, run `make`, and
the emulator will pick up the change. `test_pld_literal.c` will then
flag any divergence from a hand-written line-by-line transcription of
the original equations — useful as a sanity check that the equation
edits parsed the way you intended.
