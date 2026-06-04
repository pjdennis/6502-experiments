# BBC BASIC IV (6502) — Code Composition Analysis

## What this is

An analysis of **how the BBC BASIC version 4 source code divides up by capability
area** — what fraction of the interpreter is floating point, the built-in
assembler, the expression evaluator, I/O, and so on.

## Source

- **File:** [`Basic4.src`](./Basic4.src) — the assembly source for **65C02 BBC BASIC IV**.
- **Origin:** J.G. Harston's BBC BASIC archive, `Basic4.zip`, from
  <https://mdfs.net/Software/BBCBasic/BBC/Basic4.zip> (catalogued at
  <https://mdfs.net/Software/BBCBasic/6502/>).
- **Identity (from the ROM header in the source):** ROM title `BASIC`, ROM
  version `04`, copyright `(C)1984 Acorn`. This is the canonical Acorn/Sophie
  Wilson BBC BASIC 4 that shipped in the BBC Master, targeting a **16 KB**
  sideways ROM that loads at `&8000`.
- **Form:** The source is itself a **BBC BASIC program** that uses BASIC's own
  built-in 6502 assembler (`[OPT...]` blocks, `.label`, `EQUB/EQUW/EQUS`). A
  handful of lines (`OPT`, `SAVE`, `DEF FN` helpers) are the build harness and
  are excluded from the ROM totals below.

## Two metrics: source lines and ROM bytes

This analysis is given **both** ways:

1. **Source lines per region** — readable, easy to follow in the listing.
2. **Assembled ROM bytes per region** — the "true" footprint in the 16 KB image.

The byte figures are exact, not estimated, and they did **not** require a BBC
BASIC interpreter to assemble. This disassembly labels every routine `L<hexaddr>`
where the hex *is* the assembled address (verified: `.L800E` lands exactly where
the header byte arithmetic predicts). So the byte size of each routine is simply
the delta to the next label. All 1,286 numeric labels run monotonically from
`&8000` to `&BFCE`, and the per-region byte spans sum to **exactly 16,384**.
[`bytes.py`](./bytes.py) reproduces this against [`Basic4.src`](./Basic4.src);
the assembled image `Basic4` (16,384 bytes) from mdfs.net was used only to
confirm the total.

**The ROM is essentially 100% full** — the only slack is **10 bytes**: a 5-byte
`"Roger"` string (an Easter egg that also seeds `RND`) and a 5-byte zero pad to
the final page boundary.

## Byte-accurate breakdown (% of the 16,384-byte ROM)

| Capability area | Bytes | % ROM | (line %) |
|---|---:|---:|---:|
| **Floating-point & math** | 2,789 | **17.0%** | 16.6% |
| **Expression evaluator** | 2,116 | **12.9%** | 14.0% |
| **Control flow** | 1,699 | **10.4%** | 9.8% |
| **I/O, OS interface & graphics** | 1,630 | **9.9%** | 11.6% |
| **Variables & arrays** | 1,481 | **9.0%** | 9.0% |
| **Built-in 6502 assembler** | 1,381 | **8.4%** | 8.8% |
| **Tokeniser & keyword tables** | 1,309 | **8.0%** | 5.2% |
| **Number ↔ string conversion** | 987 | **6.0%** | 6.3% |
| **Program editing & management** | 966 | **5.9%** | 5.9% |
| **Interpreter core & dispatch** | 857 | **5.2%** | 5.3% |
| **Strings & string functions** | 466 | **2.8%** | 2.9% |
| **Misc built-in functions** | 348 | **2.1%** | 2.8% |
| **Startup / ROM header / init** | 200 | **1.2%** | 0.8% |
| **Error-handling machinery** | 145 | **0.9%** | 0.8% |
| **Unused padding** | 10 | **0.1%** | — |

The two metrics agree closely, cross-validating the categorisation. The notable
mover is the **tokeniser (5.2% line → 8.0% byte)**: the keyword table is
line-cheap but byte-heavy — ~129 keyword strings, each a name plus a token and a
flag byte, is roughly 1 KB of pure data. Floating point's lead widens slightly
too because its polynomial-coefficient tables are byte-dense.

### I/O, OS interface & graphics — 9.9% (1,630 bytes), decomposed

A natural assumption is that this bucket is mostly thin pass-throughs to the BBC
MOS. That's true for *part* of it — but roughly half is genuine console
formatting/parsing logic that never touches the OS beyond a final `OSWRCH`.

| Routine group | Bytes | % of I/O | Shim or logic? |
|---|---:|---:|---|
| `PRINT` + print-field formatting (`@%`, `TAB(x,y)`, `SPC`, comma fields, `~`, `'`, `;`) | 296 | 18.2% | **logic** — field widths, padding, layout |
| `INPUT` / `INPUT#` | 288 | 17.7% | **logic** — prompts, comma/line splitting, per-field convert |
| Graphics/screen verbs: `GCOL COLOUR MODE MOVE DRAW PLOT CLG CLS VDU REPORT` | 260 | 16.0% | mostly **shim** (`VDU 18/22/25/16/12…`); only `MODE` has real memory-limit logic |
| Output helpers: print-char (`LISTO`), **detokeniser**, hex out, space padding | 185 | 11.3% | **logic** — esp. token→keyword expansion for `LIST`/`REPORT` |
| Line input (`OSWORD 0`) + newline | 123 | 7.5% | mostly **shim** (control-block setup + `OSWORD 0`) |
| `SAVE OSCLI EXT= PTR= CLOSE BPUT` | 122 | 7.5% | **shim** — marshal args → `OSFILE/OS_CLI/OSARGS/OSFIND/OSBPUT` |
| `SOUND ENVELOPE WIDTH` | 93 | 5.7% | **shim-ish** — evaluate N params into a block → `OSWORD` |
| `PRINT#` (write to file) | 85 | 5.2% | logic-ish — marshal each value → `OSBPUT` |
| `PRINT` inline ROM text + `OSWORD 5` byte read + `NEW`-prog | 69 | 4.2% | mixed |
| File *functions*: `PTR BGET OPENIN OPENOUT OPENUP` (+`PI`) | 58 | 3.6% | **shim** → `OSFIND/OSBGET/OSARGS` |
| Functions: `NOT POS USR VPOS` | 51 | 3.1% | mixed (`POS/VPOS`→`OSBYTE`; `USR` calls code) |

**Takeaway:** the graphics verbs really *are* thin (~260 bytes for 10
statements, ≈26 bytes each — evaluate operands, emit a `VDU` sequence), and the
file/`SAVE`/`OSCLI` plumbing is pure marshalling. But the bucket is large mainly
because of `PRINT` field formatting, `INPUT` parsing, and the output helpers
(incl. the **detokeniser** that rebuilds keyword text for `LIST`) — together
~770 bytes (~47% of the bucket) of real interpreter logic with no OS pass-through
involved. If "console formatting/parsing" were split out from "OS shims," the
true thin-shim portion of this bucket is only ~5% of the ROM, not ~10%.

> Note: a couple of general-purpose helpers in the "output helpers" span
> (a BASIC-stack space check, a zero-page copy) aren't strictly I/O — ~30 bytes
> that inflate this bucket slightly.

## Method & caveat (line metric)

Every routine in the 8,237-line source was read and assigned to one capability
area by line range; [`categorize.py`](./categorize.py) sums those ranges.

The metric is **source lines per functional region** (a readable proxy), *not*
assembled bytes. The two track each other well because the code is almost
entirely one-instruction-per-line 6502 assembly — the main exceptions are the
dense data tables (keyword table, FP constants), which are line-cheap but
byte-cheap too. 49 build-harness lines are excluded, leaving **8,188 lines**
analysed.

## Top-level breakdown (% of analysed ROM source)

| Capability area | Lines | % |
|---|---:|---:|
| **Floating-point & math** | 1,357 | **16.6%** |
| **Expression evaluator** | 1,150 | **14.0%** |
| **I/O, OS interface & graphics** | 951 | **11.6%** |
| **Control flow (FOR/GOSUB/PROC/ON/…)** | 806 | **9.8%** |
| **Variables & arrays** | 734 | **9.0%** |
| **Built-in 6502 assembler** | 720 | **8.8%** |
| **Number ↔ string conversion** | 516 | **6.3%** |
| **Program editing & management** | 484 | **5.9%** |
| **Interpreter core & dispatch** | 437 | **5.3%** |
| **Tokeniser & keyword tables** | 426 | **5.2%** |
| **String handling & functions** | 238 | **2.9%** |
| **Misc built-in functions** | 233 | **2.8%** |
| **Startup / ROM header / init** | 68 | **0.8%** |
| **Error-handling machinery** | 68 | **0.8%** |

> Statement execution as a whole — *Interpreter core & dispatch* (5.3%) plus
> *Control flow* (9.8%) — is ~15%, making "running the program" collectively the
> largest activity, just ahead of floating point. Treated as single coherent
> subsystems, **floating point (16.6%)** and the **expression evaluator (14.0%)**
> are the two biggest single areas.

## Interesting sub-breakdowns

### Floating-point & math — 16.6%
The standout: math dominates this 8-bit BASIC, reflecting its reputation for an
accurate 5-byte (40-bit) floating-point system.
| Sub-area | Lines | % ROM |
|---|---:|---:|
| Transcendental library (SIN COS TAN ASN ACS ATN LN LOG EXP SQR RAD DEG) **+ FP multiply/divide** | 906 | 11.1% |
| FP core: integer↔real, normalise, float→int, FP add/subtract | 334 | 4.1% |
| FP constants (π/2, 2/π, log/exp/atn/sin polynomial series) | 53 | 0.6% |
| Integer division (used by `DIV`/`MOD`) | 48 | 0.6% |
| FP routine-entry vector table | 16 | 0.2% |

The transcendentals are implemented with **polynomial (minimax) series**, whose
coefficients are the constant tables at the end of the ROM (`LBF74` SIN/COS,
`LBF97` ATN, `LBFCE` EXP, `LBF51` LN).

### Expression evaluator — 14.0%
| Sub-area | Lines | % ROM |
|---|---:|---:|
| Core leveled evaluator (precedence levels 7→3: OR/EOR, AND, compares, +−, ∗/DIV/MOD) | 678 | 8.3% |
| Runtime value-stack management (push/pop int/real/string) | 146 | 1.8% |
| Level 1 — values, indirection (`?` `!` `$`), `&hex`, literals, variables | 99 | 1.2% |
| `ABS` / negate / unary minus / string-value parse | 82 | 1.0% |
| Level 2 — exponentiation `^` | 60 | 0.7% |
| Integer-eval helpers | 51 | 0.6% |
| `EVAL` | 34 | 0.4% |

A classic **recursive-descent precedence cascade**: seven nested levels, each
looping over its operators before deferring to the next level down.

### Built-in 6502 assembler — 8.8%
A single 720-line block (`795–1514`). Notably self-contained: a packed
3-letter mnemonic table (split low/high byte halves), an opcode base table
grouped by addressing class, the addressing-mode resolver, and `EQUB/EQUW/EQUD/
EQUS` pseudo-ops. That one feature is ~1/11th of the whole language.

### I/O, OS interface & graphics — 11.6%
Spread across many small handlers rather than one block: `PRINT` + field
formatting (173), `INPUT`/`INPUT#` (151), the graphics/screen verbs
`GCOL/COLOUR/MODE/MOVE/DRAW/PLOT/CLG/CLS/VDU` (148), low-level print/detokenise/
number-output helpers (123), `OSWORD` line input (62), file verbs
`SAVE/OSCLI/CLOSE/BPUT/PTR=` (60), `SOUND/ENVELOPE/WIDTH` (57), the file
*functions* `OPENIN/OUT/UP/BGET/PTR` (50), `PRINT#` (49). Almost everything here
is a thin shim over the BBC MOS (`OSWRCH/OSWORD/OSBYTE/OSFILE/OSFIND/…`), which
keeps it small.

### Number ↔ string conversion — 6.3%
| Sub-area | Lines | % ROM |
|---|---:|---:|
| Float → decimal string (`@%` G/E/F formats, rounding) | 257 | 3.1% |
| Scan decimal number (parse a numeric literal, incl. `E` exponent) | 129 | 1.6% |
| Integer & hex (`~`) output | 72 | 0.9% |
| `VAL` / `INT` | 58 | 0.7% |

### Program editing & management — 5.9%
`EDIT`/`LIST` (172), `RENUMBER` (132), `LOAD` + find-TOP (74),
`CHAIN/RUN/LOAD/OLD/END` (34), program-line search (27), `DELETE` (23),
`AUTO` (22).

### A note on error handling
The *machinery* (the `BRKV` handler, `ON ERROR`, the default
`REPORT:IF ERL...` handler) is only ~68 lines (0.8%). But that **understates**
error handling: the 50 individual error messages (`Division by zero`,
`Type mismatch`, `No room`, `Subscript`, …) are emitted **inline** as
`BRK:EQUB n:EQUS "..."` right where each error is detected, so ~50 more lines of
error text are distributed across every other category rather than centralised.
