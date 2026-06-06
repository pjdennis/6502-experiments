# Plan: a banked Prog8 target for the wendy2 machine

Establish a new **external** Prog8 compilation target (`wendy2`) that
exposes the wendy2/wendy2c memory-banking hardware, and demonstrate
banking of **code and data** running on the emulator in `wendy2c` mode.

This is a planning document. No code is changed by committing it.
Companion docs: [`PLAN.md`](./PLAN.md), [`ASM_MIGRATION_PLAN.md`](./ASM_MIGRATION_PLAN.md),
[`upstream/README.md`](./upstream/README.md) (the existing custom-target
scaffolding this builds on).

---

## 1. Goal & scope

* A custom upstream-Prog8 target `wendy2` (a `.properties` file +
  `libraries/wendy2/`), sibling to the existing `upstream/nmos` target,
  so banked programs compile with the official `prog8c.jar` -- "external
  if possible" satisfied.
* A small **banking runtime** in the target's syslib (hand-rolled, since
  upstream's `@bank`/`callfar` are hard-gated to cx16/c64/c128 -- see S3).
* Demo `.p8` programs + LCD goldens + a test runner that prove banked
  **data** and banked **code** work on the emulator under `--machine wendy2c`.

Out of scope: real-hardware bring-up (the emulator is the oracle);
self-hosting/p8c support (upstream prog8c is primary; a p8c path is a
later option, S9).

---

## 2. The hardware/emulator banking model (verified)

All facts below were read from the emulator + PLD, not assumed.

### 2.1 Address map
* **`$0000-$7FFF` -- fixed RAM, always.** Every `romcs`/`viacs` PLD term
  requires `a15=1` (`chips/clock_22v10_pld_generated.h:10-21`), so the
  lower 32K is RAM in every bank configuration. Holds ZP (`$00-$FF`),
  stack (`$0100-$01FF`), and the resident program.
* **`$F000-$F7FF` -- VIA 6522, always mapped**, independent of bank bits
  (`pld_viacs` ignores `c0..c4`, `clock_22v10_pld_generated.h:14-17`).
  This is essential: the bank-select register *is* a VIA port, so it must
  stay reachable in every bank.
* **`$8000-$FFFF` (minus the VIA) -- the banked window.** ROM when the
  bank config is `$00` or `$10`; otherwise a RAM bank
  (`pld_romcs`/`pld_ramcs`, lines 10-21).
* The lower and upper CPU windows always land in **disjoint physical
  RAM halves** (CPU A15 -> RAM A14, `chips/ram_628128.c:5-27`), so
  switching the upper bank never disturbs the lower 32K.

### 2.2 Bank-select register & the "8 upper banks"
Bank config = VIA **PORT B bits 0-4** (`base_config_wendy2c.inc:6-7`,
`BANK_PORT=PORTB`, `BANK_MASK=%00011111`). Decoding the PLD r-bit
equations (`clock_22v10_pld_generated.h:23-41`) for the upper window:

* **bit 3 (`c3`) must stay 0** -- it drives *lower*-window banking; with
  `c3=0` the lower 32K maps to a fixed physical region regardless of the
  other bits. (We do not use lower banking.)
* **bit 4 (`c4`) = 1 enables upper-window RAM banking.** With `c4=0` the
  upper window does not bank by `c0-c2`.
* **bits 0-2 (`c0..c2`) select the bank.** So the upper-window configs are
  `PORTB = $10 | n`:

  | PORTB | config | upper window |
  |-------|--------|--------------|
  | `$10` | %10000 | **ROM / boot** (bank 0) |
  | `$11`..`$17` | %10001..%10111 | **RAM banks 1-7** |

  That is the user's "8 upper banks": bank 0 = the boot ROM view, banks
  1-7 = switchable RAM, lower 32K fixed throughout. These are exactly the
  `%10xxx` values `verification_wendy2c.s:95-150` already exercises and
  passes on this emulator (and real hardware). (Each PORTB value actually
  maps two 16K half-windows to physical banks `2n`/`2n+1`; the demos use
  a single window address per bank and a **probe test (T1) pins down the
  precise distinct-bank set empirically** rather than trusting this
  derivation.)

### 2.3 What is fixed vs. switched, and the vector caveat
* Fixed across a switch: `$0000-$7FFF` (code/ZP/stack/data) and the VIA
  at `$F000-$F7FF`.
* Switched: `$8000-$EFFF` and `$F800-$FFFF`. **The CPU vectors
  `$FFFA-$FFFF` live in the banked window**, so when a RAM bank is active
  the IRQ/NMI vectors come from that bank. The bank-switch helper
  therefore brackets switches with `SEI`/`CLI`, and the demos do not rely
  on interrupts. (Documented as a constraint, not solved here.)

### 2.4 Boot/load path (how a wendy2c program actually runs)
From `p8c/__main__.py:38,63-90`: the emulator runs a **boot ROM at
`$8000-$FFFF`** (`upload_and_run_eeprom_wendy2c.s` -> `wendy2c_boot.bin`)
with `--machine wendy2c --serial-input <framed> --cycle-cap N`. The boot
ROM receives the program over serial (framed by
`emulator/wendy2_upload.py`), writes it to **RAM at `$4000`**, and jumps
to it. So the program runs from the fixed lower 32K -- exactly where
banked code needs its switch/trampoline routines to live.

### 2.5 Output & test capture
The HD44780 LCD (4-bit, via PORTA/PORTB). The emulator prints the final
LCD frame on **stderr** at end-of-run (`emu_wendy2c.c:748-754`,
`  |row|` lines); `--lcd-trace PATH` dumps a frame per change. The
existing `prog8/tests/test_e2e_lcd.py` already asserts on those `|...|`
rows -- the wendy2 test runner reuses that mechanism.

---

## 3. Upstream Prog8 capability & the gap

From the v12.1.1 jar (full findings in this session's research):

* **Custom targets are first-class** via `-target foo.properties`
  (`ConfigFileTarget`). Keys: `cpu`, `encoding`, `output_type`,
  `load_address`, `memtop`, `bss_highram_start/end`,
  `bss_goldenram_start/end`, `io_regions`, `zp_scratch_*`,
  `zp_fullsafe/kernalsafe/basicsafe`, `virtual_registers`, `library`,
  `custom_launcher_code`, `assembler_options`. Assembler is always 64tass.
* A custom target must ship `libraries/<name>/syslib.p8` providing the
  `sys`, `cx16` (the 16 virtual registers `r0..r15`), and
  `p8_sys_startup` blocks (incl. `init_system`, `cleanup_at_exit`,
  `sys.exit*`). The repo's `upstream/libraries/nmos/syslib.p8` is the
  working template.
* **Banking must be hand-rolled.** `@bank N` extsubs and the
  `callfar()`/`callfar2()` builtins exist but their codegen is gated by a
  literal `targetName in {cx16,c64,c128}` check -- a custom target gets
  *"callfar is not supported on the selected compilation target."* The
  `rombank()`/`rambank()` helpers are ordinary cx16 *library* code, not
  builtins. There is no `.properties` key for a bank register, and no
  per-variable `@bank` data placement.

**Conclusion:** define our own bank helpers + far-call trampoline in
`libraries/wendy2/`, and access banked data manually via `@(addr)` /
`peek`/`poke`. No compiler changes needed.

---

## 4. Target design

### 4.1 `upstream/wendy2.properties`
```
cpu = 65c02                 ; wendy2c is a 65C02 (stz/bra used by demos)
encoding = cp437
output_type = RAW
load_address = $4000        ; matches the boot-ROM serial-upload model
memtop = $8000              ; program + BSS live entirely in $4000-$7FFF
bss_highram_start = 0       ; banking is manual; no compiler-managed hi BSS
bss_highram_end = 0
bss_goldenram_start = 0
bss_goldenram_end = 0
io_regions = $f000-$f7ff    ; VIA -- compiler must not allocate here
zp_scratch_ptr = $f8        ; (mirror nmos.properties ZP scratch layout)
zp_scratch_b1 = $fa
zp_scratch_reg = $fb
zp_scratch_w1 = $fc
zp_scratch_w2 = $fe
zp_fullsafe = $30-$f7
zp_kernalsafe = $30-$f7
zp_basicsafe = $30-$f7
virtual_registers = $02
library = ./libraries/wendy2
custom_launcher_code =
assembler_options =
```
Notes: `memtop=$8000` keeps every prog8 variable in the fixed lower 32K;
the banked window is touched only through explicit windowed addresses, so
the compiler never needs to know it's banked. ZP `$00-$2F` left for the
VIA shadow + bank state + the runtime's pointers.

### 4.2 `upstream/libraries/wendy2/syslib.p8`
Start from `libraries/nmos/syslib.p8` and change:
* **`sys.exit*` / `p8_sys_startup.cleanup_at_exit`** end with `STP` (the
  wendy2c "halt"; the emulator dumps the LCD on STP / cycle cap). There is
  no `$F00F` exit syscall in wendy2c mode (that's the nmos machine).
* **`init_system`**: set VIA DDRA/DDRB for the 4-bit LCD + bank bits
  (mirror `base_config_wendy2c.inc` + the existing init), HD44780 4-bit
  init, and select a known default bank (`$10`). Keep a **PORTB shadow
  byte in ZP** so bank/LCD-E bits compose without read-back surprises.

### 4.3 `upstream/libraries/wendy2/textio.p8` (output)
Port the 4-bit HD44780 driver (`display_routines_4bit.inc`,
`display_string*.inc`) into Prog8 `inline asmsub`s exposed as
`txt.chrout(ubyte)`, `txt.print(str)`, `txt.clear()`, `txt.print_ub`
(hex). This is the **bulk of bring-up** -- mechanical, mirrors the
existing vasm `.inc` line-for-line, validated by an LCD golden before any
banking work. (Upstream `.p8` can't `.include` the vasm `.inc` files, so
they're reimplemented.)

### 4.4 The banking runtime (`libraries/wendy2/banking.p8`)
All in the fixed lower 32K (so it survives a switch). Bank IDs 1-7;
`PORTB = $10 | (n & 7)`, preserving the LCD-E bit (bit 5) via the shadow.

* `wendy2.set_upper_bank(ubyte n)` -- `SEI`; shadow = (shadow & %11100000)
  | $10 | (n & 7); `sta PORTB`; settle nops (hardware fidelity); leaves
  IRQs masked is *not* desired, so it restores the prior I flag -- or the
  callers bracket their own critical sections. (Pick: helper does
  `SEI`...write...`CLI` only if IRQs were enabled; demos run with IRQs
  off, so plain write is fine. Decide at impl time; default to SEI/CLI.)
* `wendy2.get_upper_bank() -> ubyte`.
* `wendy2.bank_poke(ubyte n, uword win, ubyte v)` /
  `bank_peek(ubyte n, uword win) -> ubyte` -- save current bank, switch to
  `n`, access `$8000+win` (or absolute `win` in `$8000-$EFFF`), restore.
  The save/switch/access/restore is the proven `verification_wendy2c.s`
  pattern.
* `wendy2.callfar(ubyte n, uword win) -> ubyte` -- the **far-call
  trampoline** (our hand-rolled `x16jsrfar` equivalent): save bank, switch
  to `n`, `jsr (win)` into `$8000+`, restore bank, return A. Lives in the
  fixed region by construction (it's a normal asmsub at `$4000+`).

Banked **data** = `bank_peek/poke` or a thin pointer wrapper. Banked
**code** = `callfar` to a routine previously copied into a bank's window.

---

## 5. Build & run harness

Mirror `p8c --run` (`p8c/__main__.py:81-90,179-182`):

`upstream/wendy2_run.sh <demo.p8> [--lcd-out FILE]`:
1. `cd upstream && java -jar /tmp/prog8c.jar -target wendy2.properties
   -out OUT demo.p8` -> RAW binary at `$4000`.
2. Frame it: `python3 ../emulator/wendy2_upload.py OUT/demo.bin -o demo.framed`.
3. Build the boot ROM once (`vasm6502_oldstyle` on
   `upload_and_run_eeprom_wendy2c.s`, as `build_boot_rom` does) ->
   `wendy2c_boot.bin`.
4. Run: `emulator.out wendy2c_boot.bin --machine wendy2c
   --serial-input demo.framed --cycle-cap N` -> capture LCD frame from
   stderr.

(64tass + the prog8 jar + the emulator are the only host deps; all were
installed/built in this session's container -- see `setup`-style notes in
`upstream/`.)

---

## 6. Demo programs + tests

Each `.p8` lands a known string on the 16x2 LCD; the runner diffs the
captured frame against a `.expected.lcd` golden (same discipline as
`test_e2e_lcd.py`). All live under `upstream/libraries/wendy2/tests/` (or
`prog8/tests/wendy2/`).

* **T1 `bank_probe.p8` -- data banking proof + bank-set discovery.**
  For `n in 1..7`: `bank_poke(n, $2000, $40+n)`. Then read all back with
  `bank_peek` and verify each equals `$40+n` (proves writes land in
  distinct banks and the lower-32K program is undisturbed). Print
  `bank N OK` / count of distinct banks. *This test empirically fixes the
  usable bank set* referenced in S2.2.
  Golden: `|bankprobe  OK   |` (exact text TBD).

* **T2 `banked_data.p8` -- banked arrays.** Fill `$2000..$20FF` in bank 1
  with `i`, and in bank 2 with `255-i`; then for a few indices read
  `bank_peek(1,..)+bank_peek(2,..)` and assert it's always `255`; print
  the checksum in hex. Demonstrates banked **data** that exceeds a single
  32K map.

* **T3 `banked_code.p8` -- banked code via far-call.** At startup copy a
  tiny routine (hand-written `%asm{{ }}`, position-correct for `$8000`)
  into bank 3's window, then `wendy2.callfar(3, $8000)`; the routine
  returns `A=$2A`; print it as `*`. Proves a `jsr` into a switched-in bank
  works and control returns with the original bank restored.

* **T4 `bank_counters.p8` -- round-trip/persistence.** Keep a 1-byte
  counter at `$2010` in each of banks 1-7; loop 3 times incrementing every
  bank's counter; finally read them out -> expect `3 3 3 3 3 3 3`. Stresses
  repeated switching + restore and that banks retain state.

A `test_wendy2_banking.py` registers one test per `.p8`/`.expected.lcd`
pair, skips if `prog8c.jar`/`64tass`/`vasm`/emulator are absent, and is
wired into `make prog8-test` (or a new `make wendy2-test`).

---

## 7. Milestones

* **M0 -- target skeleton.** `wendy2.properties` + minimal syslib
  (`sys`/`cx16`/`p8_sys_startup`, exit=STP). A `main { }` that just `STP`s
  compiles and runs to a blank-LCD golden. Proves the custom target +
  boot-upload + emulator chain end-to-end.
* **M1 -- output.** `textio.p8` 4-bit HD44780 driver; `hello.p8` prints
  to the LCD (golden). No banking yet.
* **M2 -- bank register + probe.** `set_upper_bank`/`get_upper_bank`/
  `bank_peek`/`bank_poke`; T1 green; the usable bank set is recorded.
* **M3 -- banked data.** T2, T4 green.
* **M4 -- banked code.** `callfar` trampoline; T3 green.
* **M5 -- docs + CI.** README for the target; `make wendy2-test`; link
  from `PLAN.md`.

Critical path is **M1** (the LCD driver port) -- it's the only large piece;
banking itself (M2-M4) is small once output works.

---

## 8. Risks / open questions

* **LCD driver port (largest task).** Must match the emulator's HD44780
  protocol/timing exactly. Mitigate by mirroring `display_routines_4bit.inc`
  and gating M1 behind an LCD golden before touching banking.
* **Exact bank count (7 vs 8).** With `c3=0` the PLD gives 7 switchable
  RAM banks (`$11-$17`) plus the ROM/boot view (`$10`). If a true 8th RAM
  bank is required, T1's probe should also test whether any `c3=1`/other
  value yields an 8th *without* disturbing the lower 32K -- but the safe,
  lower-fixed model is 7. Flag the discrepancy with the user's "8."
* **Vectors in banked space.** IRQs are masked during switches and unused
  by the demos; a real interrupt-driven program needs every bank's
  `$FFFA-$FFFF` populated or a fixed-region vector strategy -- deferred.
* **Assembler coupling.** This target uses 64tass (upstream's fixed
  assembler). It does not depend on the on-host-assembler migration
  ([`ASM_MIGRATION_PLAN.md`](./ASM_MIGRATION_PLAN.md)); the two are
  independent.
* **memtop headroom.** `$4000-$7FFF` (16 KB) for code+vars; the LCD driver
  + banking runtime are small, but a large demo could crowd it. Lower
  `load_address` toward `$0200` if needed (the boot ROM can upload there
  too -- verify against `upload_and_run_eeprom_wendy2c.s`).

## 9. Optional follow-on: p8c support

p8c already has a `wendy2c` target and now accepts raw `%asm{{ }}` blocks,
so the same banking runtime (as inline asm) could be offered to p8c-built
programs later -- useful for the self-host story, but not required for
this target. Upstream prog8c is the primary, "external" path per the
request.
</content>
