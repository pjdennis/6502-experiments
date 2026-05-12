# INVESTIGATION — wendy2c emulator extension (Phase 0)

This note records the answers to the five investigate-first items called out
in `WENDY2_EMULATOR_PLAN.md`. Each answer cites the source-of-truth file
lines so the later phases can be implemented against pinned facts rather than
guesses.

Branch: `wendy2-emulator`, based on the current `text-editor` lineage as it
exists on `origin/wendy2-emulator`. (We were instructed to just work off
`wendy2-emulator` rather than re-cut from `text-editor` directly.)

Baseline test state (recorded so any later regression is unambiguous):

- `make` — clean.
- `./asmtestgen.sh` — exit 0. 501 asm17 tests, 442 self-hosted test_runner
  tests, 30 directory-mode tests, bootstrap self-assembly byte-identical
  (`17/out/asm.out == 17/out/asm_2.out`).
- `python3 run_tests.py -q` — 501 passed.
- `python3 editor/tests/editor_tests.py -q` — 1466 passed, 20 skipped.

---

## 1. Serial wiring — VIA CB2 / SR / T2, RX-only

**Pinned**: serial RX path drives the VIA's CB2 (start-bit edge) + SR
(shift register) + T2 (half-bit timer). Serial TX is **unused** by any
wendy2c on-target program in the tree.

Evidence:

- `upload_and_run.inc:112` — `lda #PCR_CB2_IND_NEG_E ; CB2 independent
  interrupt negative edge`. PCR is configured for the start-bit edge.
- `upload_and_run.inc:117` — `lda #(IERSETCLEAR | ICB2 | ISR)`. Only CB2
  and SR interrupts are enabled.
- `upload_and_run.inc:449` — `lda #ACR_SR_IN_T2`. Shift register is in
  **input-from-T2** mode for the duration of a byte.
- `upload_and_run.inc:454,478` — reads `SR` to obtain the shifted-in byte;
  reading SR also clears the SR interrupt.
- `upload_and_run.inc:121, 457, 476` — T2 is loaded with
  `INITIAL_INTERVAL` / `SUBSEQUENT_INTERVAL` for half-bit timing.
- `upload_and_run.inc:236-237` — when upload completes, `ACR` and `PCR`
  are zeroed, returning CB2 to idle.

No file in the repo uses any `ACR_SR_OUT_*` mode under wendy2c
(`grep -rln 'ACR_SR_OUT' .` returns 0 hits in current wendy2c programs;
the constants are defined in `6522.inc` but unreferenced).
`upload_and_run.old.inc` uses the older CA2-driven scheme and is not
included by any current wendy2c program — keep it out of the emulator
spec.

The TRANSLATE/bit-reverse table built in `upload_and_run.inc:420-437` is
applied to every received byte after upload completes
(`upload_and_run.inc:256-258` → `translate_data`), because the SR shifts
bits in the order opposite to the wire-line order produced by the USB
serial chip. The emulator's SERIAL_USB chip (phase 13a) must therefore
present bytes to CB2/SR pre-reversed in the same convention the real chip
does, so the TRANSLATE table on the 6502 side gets the same bytes it
gets on real hardware.

Implications for phase 13:

- VIA model needs the `ACR_SR_IN_T2` mode and CB2-independent-interrupt
  edge detection for **RX only**; `ACR_SR_OUT_*` can be modelled as a
  stub that records bits in a sink for completeness, but is not
  exercised.
- Phase 13a's SERIAL_USB chip drives CB2 low (start bit), then runs T2
  for `INITIAL_INTERVAL` + 8·`SUBSEQUENT_INTERVAL` half-bit periods
  shifting one bit into SR per T2 underflow.

## 2. RAM size — 628128 (128 KiB), 17 address lines, default; emulator should still support 512 KiB

**Pinned (with one open question)**: the chip name `628128` in the plan
implies a 128 KiB SRAM with 17 address pins (A0..A16). The CPU provides
A0..A14 (15 lines), and the PLD generates `R15` and `R16` as the two
high bank-select bits → 17 lines total. That matches the 628128
exactly.

But: the PLD also drives `R17` and `R18` (`22V10-wendy2c.pld:55-65`).
These are emitted unconditionally based on `C0..C4` and the address.
With the configs that on-target programs actually use
(`base_config_wendy2c.inc:8-11` — `BANK_START=%00000001`,
`BANK_STOP=%00010000`, mask `%00011111`), several bank values produce
non-zero R17/R18 in the equations. So one of:

  a. The chip is actually a 512 KiB SRAM (A0..A18, 19 address lines) and
     R17/R18 are wired.
  b. The chip is a 128 KiB SRAM (A0..A16) and R17/R18 are PLD outputs
     left unconnected on the breadboard. In that case, software that
     uses bank values where the PLD would otherwise drive R17/R18 will
     silently alias onto the lower banks.

No schematic file is present in the repo to pin this down:

```
$ find . -maxdepth 3 -name 'schematic*' -o -name '*.kicad_*' -o -name '*.sch'
(no results)
```

**Decision for the emulator**: model the full 19-bit physical address
space (`uint8_t[0x80000]`, 512 KiB) and apply all four R-bits. This is
upward-compatible with both physical chips; we will not introduce a
divergence vs. real hardware in case (a), and in case (b) we should expose
an opt-in `--ram-128k` flag that masks R17/R18 to 0 before forming the
physical address, so the emulator reproduces the aliasing behavior of a
128 KiB physical chip. Default the flag's value to `512k` since the
on-target programs in the tree behave the same way under (a); we'll flip
the default if (b) is confirmed later by inspection of the breadboard.

Phase 7 will name the module `chips/ram_628128.c/.h` for consistency
with the plan, but its constructor will take a size parameter.

## 3. LED + button bit positions — PB6 LED, button input deferred

**Pinned**:

- LED on PORTB bit 6 (`%01000000`).
  - `multitasking_test_wendy2c.s:3-4` (`LED_MASK=%01000000`,
    `LED_PORT=PORTB`).
  - `wendy2c_led_test.s:3-4` (same).
- T1 squarewave / audio output on PORTB bit 7 (`%10000000`).
  - `multitasking_test_wendy2c.s:24-25` (`T1_SQWAVE_OUT=%10000000`,
    `T1_SQWAVE_PORT=PORTB`).
- `CONTROL_BUTTON` mention exists only in commented-out lines in
  `multitasking_test_wendy2c.s:8` (`;CONTROL_BUTTON = %00100000` — PA5)
  along with `;MORSE_LED = %00010000` (PA4) and `;CONTROL_LED =
  %01000000` (PA6) on PORTA. None of these are live code in any
  wendy2c program currently in the tree.

`grep -rln CONTROL_BUTTON .` only finds it in the commented-out block of
`multitasking_test_wendy2c.s` and not in any include file driven by a
program.

**Implication for phase 11**: the LED chip subscribes to PORTB bit 6
writes; the audio sink subscribes to PORTB bit 7. The button-input
infrastructure (F-key → PORTA bit) is **deferred** — phase 11 lands
the LED + status-bar render and `led_buttons_press(bit)` API, but no
program currently reads any button bit, so the F-key wiring will sit
unused until someone adds a wendy2c program that polls PORTA. This
matches the plan's "defer button input plumbing past LED rendering and
revisit" note in the original investigation list.

## 4. LCD size — 16x2 default

**Pinned**: 16x2 is the active configuration. 20x4 is in the file but
commented out.

- `base_config_wendy2c.inc:34-37` — `DISPLAY_WIDTH=16`,
  `DISPLAY_HEIGHT=2`, `DISPLAY_LAST_LINE=DISPLAY_SECOND_LINE`.
- `base_config_wendy2c.inc:39-42` — the 20x4 block, commented out.

Display interface:

- 4-bit mode (`base_config_wendy2c.inc:32` — `DISPLAY_BITS=4`).
- Data nibble on PORTA bits 4..7
  (`base_config_wendy2c.inc:13-14` — `DISPLAY_DATA_PORT=PORTA`,
  `DISPLAY_DATA_MASK=%11110000`).
- `RS` on PORTA bit 0 (`%00000001`); `RW` on PORTA bit 3 (`%00001000`);
  busy-flag read-back on PORTA bit 7 (`BF=%10000000`).
- `E` on PORTB bit 5 (`%00100000`).

**Implication for phase 10**: default LCD chip is 16x2, expose
`--lcd-rows N --lcd-cols N` so the 20x4 path can be exercised later.

## 5. CKS / CK ordering — registered outputs, four-phase OSC tick

**Pinned**: the PLD equations at `22V10-wendy2c.pld:11-14`:

```
CKS.R = /CKS
CK.R  = CK * /CKS  +  /CK * CKS  +  /ROMCS * /CK
```

Reading `.R` as "registered output, latched on OSC rising edge using the
input values present at that edge", I traced both phases by hand:

**No-ROM case** (`/ROMCS = 1`, i.e., positive-logic `ROMCS = 0`):

| OSC tick | CKS | CK |
|---|---|---|
| 0 | 0 | 0 |
| 1 | 1 | 1 |
| 2 | 0 | 0 |
| 3 | 1 | 1 |
| 4 | 0 | 0 |

CK = CKS exactly. Confirms the PLD description: "CK ... otherwise the
same speed as CKS" (`22V10-wendy2c.pld:79-80`).

**ROM case** (`/ROMCS = 0`):

| OSC tick | CKS | CK |
|---|---|---|
| 0 | 0 | 0 |
| 1 | 1 | 0 |
| 2 | 0 | 1 |
| 3 | 1 | 1 |
| 4 | 0 | 0 |

CK runs at OSC/4 = CKS/2 with a one-OSC-tick phase delay. Confirms
"Half the speed of CKS when ROM is selected"
(`22V10-wendy2c.pld:78-80`).

The `/ROMCS * /CK` term in the equation is therefore active **when ROM
is NOT being accessed** — it boosts CK up to the CKS rate by forcing
CK to track CKS one OSC tick later. When ROM IS being accessed, that
term is 0 and CK falls back to the slower CKS-XOR rate.

The `/WR` equation `WR = /RWRB * CK` (`22V10-wendy2c.pld:18`) gates the
write strobe high during the CK-high half of any write cycle.

**Implication for phase 5 (clock_22v10) and phase 8 (CPU on bus)**:

Per OSC tick the emulator runs four phases:

1. **Latch inputs**: snapshot the values of `A11..A15`, `RWRB`, and
   `C0..C4` that combinational logic should see for this tick — these
   are whatever the CPU and VIA exposed at the *end* of the previous
   tick.
2. **Update CKS** (registered): `CKS.next = NOT (CKS_prev)`.
3. **Update CK** (registered): `CK.next` from the equation above,
   evaluated against the previous tick's CK/CKS/ROMCS.
4. **Combinational outputs** + **CK-falling-edge action**: with the new
   CKS/CK values now visible, recompute `ROMCS, RAMCS, VIACS,
   R15..R18, /WR`. On a CK falling edge (CK went 1→0 between the
   previous tick and this one), advance the CPU module by one bus
   cycle (under phase-8 strategy 1, "execute next instruction if no
   cycles are still owed, else just tick the counter").

This split avoids any combinational loop and matches how a real 22V10
schedules registered vs. combinational outputs from one clock edge.

---

## Phase 8 strategy decision

The plan listed two strategies for CPU-on-bus:

1. Per-instruction execute, credit the bus with the instruction's
   cycle count after the fact.
2. True per-cycle state-machine CPU.

User decision (recorded): **strategy 1**. Switch to strategy 2 only if
phase 13's RX path turns out to depend on intra-instruction bus order,
which is unlikely given the VIA SR-fire happens at T2 underflow — a
boundary between instructions.

## Open questions still being deferred

- **RAM physical size (128 KiB vs 512 KiB)**: see section 2. Default
  emulator behavior chosen pending a hardware-side confirmation. Will
  ask the user explicitly if any wendy2c on-target program ever stores
  to a bank whose C-value sets R17 or R18 — if so, and the program
  expects no aliasing, the chip must be 512 KiB.
- **Button bit (PA5 vs other)**: section 3. Deferred until any
  on-target program actually reads it.
