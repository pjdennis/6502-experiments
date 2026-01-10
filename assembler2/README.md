# 6502 Assembler Bootstrap Chain

A fully self-hosting 6502 assembler built through progressive bootstrapping, with no external assembler dependencies. The bootstrap starts from a minimal C program and builds up to a full-featured assembler that can assemble its own source code.

## Prerequisites

- GCC (for compiling the emulator and bootstrap assembler)
- G++ (for compiling the sidebyside utility)
- fswatch (optional, for watch mode)

## Quick Start

```bash
# Build and run the full bootstrap chain
./asmtestgen.sh

# Watch mode (rebuilds on file changes)
./gogen.sh
```

## Bootstrap Chain Overview

The assembler bootstraps through 16 progressively more capable versions:

```
asm0c.c (C bootstrap)
    |
    v
asm00.out -----> asm01.out -----> asm02.out ---> ... ---> asm06.out
(DATA-only)    (asm02 in DATA)  (first "real"           (supports
                                 assembler)              .include)
                                                            |
                        +-----------------------------------+
                        |
                        v
                  instgen07.out ---> out/inst07.asm.out
                        |                    |
                        +--------------------+
                        v
                  asm07.out ---> asm08.out ---> asm09.out ---> asm10.out
                  (inst07 concatenated with source)
                        |
                        v
                  instgen11.out ---> out/inst11.asm.out
                        |                    |
                        +--------------------+
                        v
                  asm11.out ---> asm12.out (uses .include for inst11)
                        |
                        v
                  [continues through asm13, asm14, asm15]
                        |
                        v
                  asm15.out (final, self-hosting)
                        |
                        v
                  asm15_2.out (self-assembled)
                        |
                        v
                  Verification: asm15.out == asm15_2.out
```

### Bootstrap Levels

| Level | File | Key Features |
|-------|------|--------------|
| 0 | asm00.asm | Minimal DATA-only syntax, assembled by C program |
| 1 | asm01.asm | asm02 translated to DATA format |
| 2-6 | asm02-06.asm | Progressive feature additions |
| 7-10 | asm07-10.asm | Require generated instruction tables (concatenated) |
| 11-12 | asm11-12.asm | Use `.include` for instruction tables |
| 13-15 | asm13-15.asm | Full-featured with local labels, hash tables, etc. |

## Directory Structure

```
assembler2/
├── out/                    # Generated outputs
│   ├── asm00.out           # Level 0 assembler
│   ├── asm01.out ... asm15.out
│   ├── inst07.asm.out ... inst15.asm.out
│   └── ...
├── dump/                   # Memory dumps from emulator
│   └── *.dump.bin
├── legacy/                 # Old/unused assembler versions
│
├── emulator.out            # 6502 emulator
├── sidebyside.out          # Hexdump display utility
├── asm0c.out               # C bootstrap assembler
│
├── asm00.asm - asm15.asm   # Assembler source chain
├── instgen07.asm - instgen15.asm  # Instruction table generators
├── common11.asm - common15.asm    # Shared code
├── hash_table13.asm - hash_table15.asm
├── environment11.asm
├── file_stack13.asm, file_stack15.asm
├── to_decimal13.asm, to_decimal15.asm
│
├── test.asm                # Test program
├── Makefile
├── asmtestgen.sh           # Main build script
└── gogen.sh                # Watch mode wrapper
```

## Build Scripts

| File | Description |
|------|-------------|
| `Makefile` | Builds emulator, sidebyside, C bootstrap (asm0c), and level-0 assembler (asm00) |
| `asmtestgen.sh` | Runs the full bootstrap chain from asm00 through asm15 |
| `gogen.sh` | Watch mode - rebuilds on source file changes |

## Tools

| File | Description |
|------|-------------|
| `emulator.c` | 6502 emulator that runs the assemblers |
| `asm0c.c` | Minimal C assembler for bootstrapping (DATA-only syntax) |
| `sidebyside.cpp` | Utility for displaying hexdump output side-by-side |

## Verification

The build verifies correctness by:

1. Assembling `asm15.asm` with `out/asm14.out` to produce `out/asm15.out`
2. Assembling `asm15.asm` with `out/asm15.out` (self-assembly) to produce `out/asm15_2.out`
3. Comparing the two outputs - they must be identical

If the assembler can correctly assemble itself and produce an identical binary, the bootstrap is successful.

## Testing

After a successful build, `test.asm` is assembled and executed:

```bash
out/emulator.out out/asm15_2.out 2000 /dev/null /dev/null test.asm out/test.out
out/emulator.out out/test.out 1000 /dev/null - arg1 "arg 2"
```

## Emulator Interface

The emulator provides these memory-mapped I/O routines (via JSR):

| Address | Function |
|---------|----------|
| `$F006` | Read byte from current input file (C=1 on EOF) |
| `$F009` | Write byte to output |
| `$F00C` | Write byte to stderr |
| `$F00F` | Exit program (exit code in A) |
| `$F012` | Open file for reading (filename in A/X, returns handle in A) |
| `$F015` | Close file (handle in A) |
| `$F018` | Read byte from file handle (handle in A, C=1 on EOF) |
| `$F01B` | Get argument count |
| `$F01E` | Get argument string (index in A, returns pointer in A/X) |
| `$F021` | Open file for writing |
| `$F024` | Write byte to file handle |

## Assembler Syntax (asm15)

```asm
; Comments start with semicolon
LABEL = $1234            ; Constant assignment
*     = $2000            ; Set program counter

  .zeropage              ; Switch to zero page section
  .code                  ; Switch to code section
  .include filename.asm  ; Include another file

label                    ; Global label
.local                   ; Local label (scoped to previous global)

  LDA# $42               ; Immediate
  LDAZ $00               ; Zero page
  LDA $1234              ; Absolute
  LDA,X                  ; Absolute,X
  LDA,Y                  ; Absolute,Y
  LDAZ,X                 ; Zero page,X
  LDA(),Y                ; Indirect,Y

  DATA $01 $02 $03       ; Raw bytes
  DATA "string"          ; ASCII string
  DATA <label >label     ; Low/high byte of address

  BRK $01 "error" $00    ; BRK with inline error message
```
