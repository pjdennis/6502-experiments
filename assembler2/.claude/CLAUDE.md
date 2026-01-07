# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Full build and verification
./asmtestgen.sh

# Watch mode (rebuilds on source changes)
./gogen.sh

# Build just the emulator and initial bootstrap
make
```

The build succeeds when `asm4b13.out == asm4b13_2.out` (self-assembly verification).

## Architecture

This is a self-hosting 6502 assembler built through progressive bootstrapping. The final assembler (`asm4b13.asm`) can assemble its own source code.

### Bootstrap Chain

External vasm assembles `asm4v.asm` → `asm4v.out`, which then assembles progressively more capable versions (`asm4b.asm` → `asm4b2.asm` → ... → `asm4b13.asm`). Each version adds features needed by the next.

### Key Components

- **Instruction generators** (`instgen*.asm`): Generate `inst*.asm.out` files containing pre-computed instruction hash tables. These are `.include`d by the assemblers to avoid runtime initialization.

- **Hash tables**: Used for both label lookup (`LHASHTAB` at $1F00) and instruction lookup (`IHASHTAB`). Hash entries are stored on a heap (`MEMPL/MEMPH`).

- **Two-pass assembly**: Pass 1 collects labels, Pass 2 resolves references and emits code.

### Memory Layout (asm4b13)

- `$0000-$00FF`: Zero page variables (see `.zeropage` section)
- `$1D00`: TOKEN buffer (current token being read)
- `$1E00`: Label hash table
- `$2000+`: Generated code
- `$F000`: File stack (grows downward)

### Shared Code Pattern

Common code is factored into include files:
- `common13.asm`: Shared between `asm4b13.asm` and `instgen13.asm`
- `hash_table13.asm`: Hash table implementation (included by common13)

The hash table requires caller to define `HT_KEY`, `HT_VL`, `HT_VH` before including.

### Zero Page Conventions

Variables are allocated via `DATA $00` in `.zeropage` section. Two-byte pointers use adjacent locations with L/H suffix (e.g., `MEMPL`/`MEMPH`).

## Emulator Interface

The C emulator (`emulator.c`) provides memory-mapped I/O. Key addresses:
- `$F006`: Read byte from input
- `$F009`: Write byte to output
- `$F00C`: Write byte to error output

## Syntax Notes

The assembler uses a non-standard 6502 syntax:
- `LDA#` instead of `LDA #` (immediate mode)
- `LDAZ` for zero page addressing
- `STAZ(),Y` for indirect indexed
- `LDA,X` / `LDA,Y` for indexed absolute
