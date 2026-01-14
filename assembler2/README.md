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

The assembler bootstraps through 22 progressively more capable versions:

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
                  asm19.out (expression evaluation, assembles asm20)
                        |
                        v
                  asm20.out (conditional assembly with .ifdef/.endif)
                        |
                        v
                  asm21.out (conditional debug compilation)
                        |
                        v
                  asm21_2.out (self-assembled)
                        |
                        v
                  Verification: asm21.out == asm21_2.out
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
| 20 | asm20.asm | Conditional assembly (`.ifdef`/`.endif`), `define:label` command line |
| 21 | asm21.asm | Conditional debug compilation, produces smaller non-debug binary |

## Directory Structure

```
assembler2/
├── out/                    # Generated outputs
│   ├── asm00.out - asm21.out
│   ├── asm21_debug.out     # Debug-enabled variant of asm21
│   ├── inst07.asm.out - inst21.asm.out
│   └── ...
├── dump/                   # Memory dumps from emulator
├── legacy/                 # Old/unused assembler versions
├── tests/                  # Test suite
│   ├── run_tests.sh        # Test runner script
│   ├── asm18_tests.txt     # Tests for asm18 (reference)
│   ├── asm19_tests.txt     # Tests for asm19 (reference)
│   ├── asm20_tests.txt     # Tests for asm20
│   └── asm21_tests.txt     # Tests for asm21 (current)
│
├── emulator.out            # 6502 emulator
├── sidebyside.out          # Hexdump display utility
├── asm0c.out               # C bootstrap assembler
│
├── asm00.asm - asm21.asm   # Assembler source chain
├── instgen07.asm - instgen21.asm  # Instruction table generators
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
| `asmtestgen.sh` | Runs the full bootstrap chain from asm00 through asm20 |
| `gogen.sh` | Watch mode - rebuilds on source file changes |

## Tools

| File | Description |
|------|-------------|
| `emulator.c` | 6502 emulator that runs the assemblers |
| `asm0c.c` | Minimal C assembler for bootstrapping (DATA-only syntax) |
| `sidebyside.cpp` | Utility for displaying hexdump output side-by-side |

## Verification

The build verifies correctness by:

1. Assembling `asm21.asm` with `out/asm20.out` to produce `out/asm21.out` (without debug)
2. Assembling `asm21.asm` with `out/asm20.out` to produce `out/asm21_debug.out` (with debug)
3. Self-assembling `asm21.asm` with both variants to produce `out/asm21_2.out` and `out/asm21_debug_2.out`
4. Comparing outputs - each variant must self-assemble identically

If the assembler can correctly assemble itself and produce identical binaries, the bootstrap is successful.

The build also shows code size comparison:
```
Code size comparison:
  asm21.out (no debug):   4543 bytes
  asm21_debug.out:        4788 bytes
  Savings:                245 bytes
```

## Testing

### Test Suite

The project includes a comprehensive test suite:

```bash
# Run all tests
./tests/run_tests.sh

# Run specific test file with specific assembler
./tests/run_tests.sh tests/asm21_tests.txt out/asm21_debug.out
```

Tests verify both positive cases (correct assembly output) and negative cases (proper error detection).

### Integration Test

After a successful build, `test19.asm` is assembled and executed:

```bash
./emulator.out out/asm21_debug.out 2000 /dev/null /dev/null test19.asm out/test19.out
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

## Assembler Syntax (asm21)

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
  LDA #$10+$20           ; Expression in immediate
  LDA #$01<<$04          ; Left shift: $01 << 4 = $10
  LDA #$80>>$02          ; Right shift: $80 >> 2 = $20
  LDA #'Z'-'A'           ; Character arithmetic
  LDA $00                ; Zero page
  LDA $1234              ; Absolute
  LDA base+$10           ; Expression in address
  LDA $1234,X            ; Absolute,X
  LDA $1234,Y            ; Absolute,Y
  LDA $00,X              ; Zero page,X
  LDA (ptr+$02,X)        ; Expression in indexed indirect
  LDA ($00),Y            ; Indirect,Y
  LDA ($00,X)            ; Indirect,X

  .data $01 $02 $03      ; Raw bytes
  .data "string"         ; ASCII string
  .data value+$05        ; Expression in data
  .data <label >label    ; Low/high byte of address
  .data <addr+$10        ; Byte selector on expression
  .data label            ; 16-bit address (little-endian)

  BRK $01 "error" $00    ; BRK with inline error message

  ; Conditional assembly (asm20+)
  .ifdef SYMBOL          ; Assemble following code only if SYMBOL is defined
    LDA #$42
  .endif                 ; End conditional block
```

### Command Line

```bash
# Basic usage
./asm21.out input.asm output.bin

# With debug output (asm21_debug.out only)
./asm21_debug.out input.asm output.bin debug

# Pre-define symbols for conditional assembly
./asm21.out input.asm output.bin define:SYMBOL1 define:SYMBOL2
```

### Syntax Evolution

The assembler syntax has evolved through the bootstrap chain:

- **asm00-06**: Non-standard syntax (`LDA#`, `LDAZ`, `STAZ(),Y`)
- **asm07+**: Standard 6502 syntax (`LDA #$42`, `LDA ($00),Y`)
- **asm18**: Added `.data` directive alongside `DATA` pseudo-op
- **asm19**: Uses `.data` exclusively (removed `DATA` pseudo-op), expression evaluation
- **asm20**: Conditional assembly (`.ifdef`/`.endif`), `define:label` command line args
- **asm21**: Shift operators (`<<`, `>>`), conditional compilation for optional debug support

## Adding a New Bootstrap Step

When adding new features that require a new assembler version (e.g., asm21 → asm22), follow these steps:

### 1. Copy Source Files

Copy all assembler source files to the new version number:

```bash
# Main assembler and instruction generator
cp asm21.asm asm22.asm
cp instgen21.asm instgen22.asm

# Support files
cp common21.asm common22.asm
cp hash_table21.asm hash_table22.asm
cp file_stack21.asm file_stack22.asm
cp errors21.asm errors22.asm
cp fwdref21.asm fwdref22.asm
cp to_decimal21.asm to_decimal22.asm
cp label_scope21.asm label_scope22.asm

# Test file
cp tests/asm21_tests.txt tests/asm22_tests.txt
```

### 2. Update Include References

In each copied file, update version numbers in `.include` statements:

**asm22.asm:**
```asm
  .include out/inst22.asm.out
  .include common22.asm
  .include label_scope22.asm
  .include file_stack22.asm
  .include errors22.asm
  .include fwdref22.asm
```

**common22.asm:**
```asm
  .include hash_table22.asm
  .include to_decimal22.asm
```

**instgen22.asm:**
```asm
  .include common22.asm
```

### 3. Update asmtestgen.sh

Add the new assembler build steps and update self-hosting:

```bash
# Add after asm21 section:

# Build asm22 instruction table generator and instruction table
run_asm out/asm21.out instgen22.asm out/instgen22.out
run out/instgen22.out 2000 /dev/null out/inst22.asm.out

# Build asm22 (without and with debug)
run_asm out/asm21.out asm22.asm out/asm22.out
run_asm out/asm21.out asm22.asm out/asm22_debug.out define:enable_debug

# Self-hosting check for asm22
run_asm out/asm22.out asm22.asm out/asm22_2.out
run_asm out/asm22_debug.out asm22.asm out/asm22_debug_2.out define:enable_debug
diff out/asm22.out out/asm22_2.out && echo "OK" || { echo "MISMATCH"; exit 1; }
diff out/asm22_debug.out out/asm22_debug_2.out && echo "OK" || { echo "MISMATCH"; exit 1; }
```

**Remove the self-hosting check for asm21** (only the latest version needs self-hosting verification).

**Update the test program assembly** at the end to use the new assembler:
```bash
run_asm out/asm22_debug.out test19.asm out/test19.out
```

**Update the file_stack_test assembly** to use the new assembler:
```bash
run_asm out/asm22_debug.out tests/file_stack_test.asm out/file_stack_test.out
```

### 4. Update Test Runners

**tests/run_tests.sh** - Update defaults:
```bash
TEST_FILE="${1:-$SCRIPT_DIR/asm22_tests.txt}"
ASSEMBLER="${2:-$ASSEMBLER2_DIR/out/asm22_debug.out}"
```

**tests/run_file_stack_tests.pl** - Update assembler path:
```perl
my $assembler = $ENV{ASSEMBLER} // "out/asm22_debug.out";
```

### 5. Update gogen.sh

Add the new files to the watch list:
```bash
asm22.asm instgen22.asm common22.asm hash_table22.asm file_stack22.asm \
to_decimal22.asm errors22.asm fwdref22.asm label_scope22.asm \
tests/asm22_tests.txt \
```

### 6. Build and Verify

```bash
# Run full build chain
./asmtestgen.sh

# Verify self-hosting succeeded (look for "OK" after diff)

# Run all test suites
tests/run_tests.sh
tests/run_file_stack_tests.pl
```

### 7. Update Documentation

Update this README:
- Add the new version to the Bootstrap Chain Overview diagram
- Add an entry to the Bootstrap Levels table
- Update the Syntax Evolution section if new syntax was added
- Update version numbers throughout (e.g., "asm21" → "asm22")

### Checklist

- [ ] All source files copied with new version number
- [ ] All `.include` references updated in copied files
- [ ] asmtestgen.sh updated (build steps, self-hosting, test program)
- [ ] Previous version's self-hosting check removed
- [ ] tests/run_tests.sh defaults updated
- [ ] tests/run_file_stack_tests.pl assembler path updated
- [ ] gogen.sh watch list updated
- [ ] Build chain passes (`./asmtestgen.sh`)
- [ ] All tests pass (`tests/run_tests.sh`, `tests/run_file_stack_tests.pl`)
- [ ] README.md updated
