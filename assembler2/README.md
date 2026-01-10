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

# Run the test suite
./tests/run_tests.sh

# Watch mode (rebuilds on file changes)
./gogen.sh
```

## Bootstrap Chain Overview

The assembler bootstraps through 20 progressively more capable versions:

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
                        |
                        v
                  asm11.out ---> asm12.out (uses .include for inst11)
                        |
                        v
                  [continues through asm13-18, adding features]
                        |
                        v
                  asm18.out (assembles asm19)
                        |
                        v
                  asm19.out (final, self-hosting)
                        |
                        v
                  asm19_2.out (self-assembled)
                        |
                        v
                  Verification: asm19.out == asm19_2.out
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
| 16 | asm16.asm | Enhanced error reporting with line numbers |
| 17 | asm17.asm | Refactored (identical output to asm16) |
| 18 | asm18.asm | Added `.data` directive alongside DATA |
| 19 | asm19.asm | Uses `.data` exclusively, removes DATA pseudo-op |

## Directory Structure

```
assembler2/
├── out/                    # Generated outputs
│   ├── asm00.out - asm19.out
│   ├── inst07.asm.out - inst19.asm.out
│   └── ...
├── dump/                   # Memory dumps from emulator
├── legacy/                 # Old/unused assembler versions
├── tests/                  # Test suite
│   ├── run_tests.sh        # Test runner script
│   ├── asm18_tests.txt     # Tests for asm18 (reference)
│   └── asm19_tests.txt     # Tests for asm19 (current)
│
├── emulator.out            # 6502 emulator
├── sidebyside.out          # Hexdump display utility
├── asm0c.out               # C bootstrap assembler
│
├── asm00.asm - asm19.asm   # Assembler source chain
├── instgen07.asm - instgen19.asm  # Instruction table generators
├── common*.asm             # Shared code between asm and instgen
├── hash_table*.asm         # Hash table implementation
├── errors*.asm             # Error message definitions
├── fwdref*.asm             # Forward reference handling
├── file_stack*.asm         # Include file stack management
├── to_decimal*.asm         # Decimal conversion utilities
│
├── test19.asm              # Test program
├── Makefile
├── asmtestgen.sh           # Main build script
└── gogen.sh                # Watch mode wrapper
```

## Build Scripts

| File | Description |
|------|-------------|
| `Makefile` | Builds emulator, sidebyside, C bootstrap (asm0c), and level-0 assembler (asm00) |
| `asmtestgen.sh` | Runs the full bootstrap chain from asm00 through asm19 |
| `gogen.sh` | Watch mode - rebuilds on source file changes |

## Tools

| File | Description |
|------|-------------|
| `emulator.c` | 6502 emulator that runs the assemblers |
| `asm0c.c` | Minimal C assembler for bootstrapping (DATA-only syntax) |
| `sidebyside.cpp` | Utility for displaying hexdump output side-by-side |

## Verification

The build verifies correctness by:

1. Assembling `asm19.asm` with `out/asm18.out` to produce `out/asm19.out`
2. Assembling `asm19.asm` with `out/asm19.out` (self-assembly) to produce `out/asm19_2.out`
3. Comparing the two outputs - they must be identical

If the assembler can correctly assemble itself and produce an identical binary, the bootstrap is successful.

## Testing

### Test Suite

The project includes a comprehensive test suite:

```bash
# Run all tests
./tests/run_tests.sh

# Run specific test file
./tests/run_tests.sh tests/asm19_tests.txt
```

Tests verify both positive cases (correct assembly output) and negative cases (proper error detection).

### Integration Test

After a successful build, `test19.asm` is assembled and executed:

```bash
./emulator.out out/asm19_2.out 2000 /dev/null /dev/null test19.asm out/test19.out
./emulator.out out/test19.out 1000 /dev/null - arg1 "arg 2"
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

## Assembler Syntax (asm19)

```asm
; Comments start with semicolon
LABEL = $1234            ; Constant assignment
*     = $2000            ; Set program counter

  .zeropage              ; Switch to zero page section
  .code                  ; Switch to code section
  .include filename.asm  ; Include another file

label                    ; Global label
.local                   ; Local label (scoped to previous global)

  LDA #$42               ; Immediate
  LDA $00                ; Zero page
  LDA $1234              ; Absolute
  LDA $1234,X            ; Absolute,X
  LDA $1234,Y            ; Absolute,Y
  LDA $00,X              ; Zero page,X
  LDA ($00),Y            ; Indirect,Y
  LDA ($00,X)            ; Indirect,X

  .data $01 $02 $03      ; Raw bytes
  .data "string"         ; ASCII string
  .data <label >label    ; Low/high byte of address
  .data label            ; 16-bit address (little-endian)

  BRK $01 "error" $00    ; BRK with inline error message
```

### Syntax Evolution

The assembler syntax has evolved through the bootstrap chain:

- **asm00-06**: Non-standard syntax (`LDA#`, `LDAZ`, `STAZ(),Y`)
- **asm07+**: Standard 6502 syntax (`LDA #$42`, `LDA ($00),Y`)
- **asm18**: Added `.data` directive alongside `DATA` pseudo-op
- **asm19**: Uses `.data` exclusively (removed `DATA` pseudo-op)
