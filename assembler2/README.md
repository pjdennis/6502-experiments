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
./run_tests.py

# Watch mode (rebuilds on file changes)
./gogen.sh
```

## Bootstrap Chain Overview

The assembler bootstraps through 23 progressively more capable versions:

```
00/asm.c (C bootstrap)
    |
    v
00/out/asm.out --> 01/out/asm.out --> 02/out/asm.out --> ... --> 06/out/asm.out
(DATA-only)      (asm02 in DATA)   (first "real"              (supports
                                    assembler)                  .include)
                                                                   |
                       +-------------------------------------------+
                       |
                       v
                 07/out/instgen.out --> 07/out/inst.asm.out
                       |                        |
                       +------------------------+
                       v
                 07/out/asmc.out --> 08/out/asmc.out --> ... --> 10/out/asmc.out
                 (inst.asm.out concatenated with source)
                       |
                       v
                 11/out/instgen.out --> 11/out/inst.asm.out
                       |
                       v
                 11/out/asm.out --> 12/out/asm.out (uses .include for inst.asm.out)
                       |
                       v
                 [continues through 13-18, adding features]
                       |
                       v
                 18/out/asm.out (assembles asm19)
                       |
                       v
                 19/out/asm.out (expression evaluation)
                       |
                       v
                 20/out/asm.out (conditional assembly with .ifdef/.endif)
                       |
                       v
                 21/out/asm.out (conditional debug compilation, shift operators)
                       |
                       v
                 22/out/asm.out (macros with parameters, memory protection)
                       |
                       v
                 22/out/asm_2.out (self-assembled)
                       |
                       v
                 Verification: asm.out == asm_2.out
```

### Bootstrap Levels

| Level | Directory | Key Features |
|-------|-----------|--------------|
| 0 | 00/ | Minimal DATA-only syntax, assembled by C program |
| 1 | 01/ | asm02 translated to DATA format |
| 2-6 | 02/-06/ | Progressive feature additions |
| 7-10 | 07/-10/ | Require generated instruction tables (concatenated) |
| 11-12 | 11/-12/ | Use `.include` for instruction tables |
| 13-15 | 13/-15/ | Full-featured with local labels, hash tables, etc. |
| 16 | 16/ | Enhanced error reporting with line numbers |
| 17 | 17/ | Refactored (identical output to asm16) |
| 18 | 18/ | Added `.data` directive alongside DATA |
| 19 | 19/ | Uses `.data` exclusively, removes DATA pseudo-op |
| 20 | 20/ | Conditional assembly (`.ifdef`/`.endif`), `define:label` command line |
| 21 | 21/ | Shift operators (`<<`/`>>`), conditional debug compilation |
| 22 | 22/ | Macros (`.macro`/`.endmacro`) with parameters, heap/stack overflow protection |

## Directory Structure

```
assembler2/
├── 00/                     # Version 0 (C bootstrap + first assembler)
│   ├── asm.c               # C bootstrap assembler
│   ├── asm.asm             # First assembler source
│   └── out/                # Build outputs (asm_c.out, asm.out)
├── 01/-22/                 # Assembler versions 1-22
│   ├── asm.asm             # Assembler source
│   ├── instgen.asm         # Instruction table generator (07+)
│   ├── common.asm          # Shared code (11+)
│   ├── environment.asm     # I/O and environment (11+)
│   ├── hash_table.asm      # Hash table implementation (13+)
│   ├── file_stack.asm      # Include file stack (13+)
│   ├── to_decimal.asm      # Decimal conversion (13+)
│   ├── errors.asm          # Error messages (18+)
│   ├── fwdref.asm          # Forward reference handling (18+)
│   ├── label_scope.asm     # Label scope management (21+)
│   ├── macros.asm          # Macro support (22)
│   └── out/                # Build outputs (asm.out, instgen.out, inst.asm.out)
│
├── run_tests.py            # Test runner
├── 22/tests/               # Latest test suite
│   ├── asm22_tests.txt     # Tests for asm22 (current, 256 tests)
│   ├── file_stack_tests22.txt  # File stack tests (30 tests)
│   ├── file_stack_test22.asm   # File stack test harness
│   └── ...                 # Any version-specific test data
├── tests/                  # Legacy test data and older test suites
│
├── legacy/                 # Old/unused files
├── out/                    # Root-level test outputs
│
├── emulator.c              # 6502 emulator
├── sidebyside.cpp          # Hexdump display utility
├── Makefile                # Builds emulator, sidebyside, C bootstrap
├── asmtestgen.sh           # Main build script (full bootstrap chain)
└── gogen.sh                # Watch mode wrapper
```

## Build Scripts

| File | Description |
|------|-------------|
| `Makefile` | Builds emulator, sidebyside, and C bootstrap (`00/out/asm_c.out`) |
| `asmtestgen.sh` | Runs the full bootstrap chain from version 00 through 22 |
| `gogen.sh` | Watch mode - rebuilds on source file changes |

## Tools

| File | Description |
|------|-------------|
| `emulator.c` | 6502 emulator that runs the assemblers |
| `00/asm.c` | Minimal C assembler for bootstrapping (DATA-only syntax) |
| `sidebyside.cpp` | Utility for displaying hexdump output side-by-side |

## Verification

The build verifies correctness by:

1. Assembling `22/asm.asm` with `21/out/asm_debug.out` to produce `22/out/asm.out` (without debug)
2. Assembling `22/asm.asm` with `21/out/asm_debug.out` to produce `22/out/asm_debug.out` (with debug)
3. Self-assembling `22/asm.asm` with both variants to produce `22/out/asm_2.out` and `22/out/asm_debug_2.out`
4. Comparing outputs - each variant must self-assemble identically

If the assembler can correctly assemble itself and produce identical binaries, the bootstrap is successful.

The build also shows code size comparison:
```
Code size comparison:
  asm.out (no debug):     6382 bytes
  asm_debug.out:          6801 bytes
  Difference:             419 bytes
```

## Testing

### Test Suite

The project includes a comprehensive test suite (286 tests):

```bash
# Run all tests
./run_tests.py

# Run with verbose output
./run_tests.py -v
```

Tests verify both positive cases (correct assembly output) and negative cases (proper error detection).

### Integration Test

After a successful build, `test19.asm` is assembled and executed:

```bash
./emulator.out 22/out/asm_debug.out 2000 /dev/null /dev/null test19.asm out/test19.out
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

## Assembler Syntax (asm22)

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

  ; Macros (asm22+)
  .macro ADDPTR ptr val  ; Define macro with parameters
  CLC
  LDA ptr
  ADC #val
  STA ptr
  LDA ptr+$01
  ADC #$00
  STA ptr+$01
  .endmacro

  ADDPTR $10 $05         ; Invoke macro (substitutes ptr=$10, val=$05)
```

### Command Line

```bash
# Basic usage (run via emulator)
./emulator.out 22/out/asm.out 2000 /dev/null /dev/null input.asm output.bin

# With debug output
./emulator.out 22/out/asm_debug.out 2000 /dev/null /dev/null input.asm output.bin debug

# Pre-define symbols for conditional assembly
./emulator.out 22/out/asm.out 2000 /dev/null /dev/null input.asm output.bin define:SYMBOL1 define:SYMBOL2

# Enable small heap for testing (debug build only)
./emulator.out 22/out/asm_debug.out 2000 /dev/null /dev/null input.asm output.bin small_heap
```

### Syntax Evolution

The assembler syntax has evolved through the bootstrap chain:

- **asm00-06**: Non-standard syntax (`LDA#`, `LDAZ`, `STAZ(),Y`)
- **asm07+**: Standard 6502 syntax (`LDA #$42`, `LDA ($00),Y`)
- **asm18**: Added `.data` directive alongside `DATA` pseudo-op
- **asm19**: Uses `.data` exclusively (removed `DATA` pseudo-op), expression evaluation
- **asm20**: Conditional assembly (`.ifdef`/`.endif`), `define:label` command line args
- **asm21**: Shift operators (`<<`, `>>`), conditional compilation for optional debug support
- **asm22**: Macros (`.macro`/`.endmacro`) with parameters, heap/stack overflow protection

## Adding a New Bootstrap Step

When adding new features that require a new assembler version (e.g., asm22 to asm23):

### 1. Create New Version Directory

```bash
cp -r 22/ 23/
mkdir -p 23/tests
cp 22/tests/asm22_tests.txt 23/tests/asm23_tests.txt
```

Since source files no longer have version suffixes, the `.include` directives inside the copied files need no changes.

### 2. Update asmtestgen.sh

Add the new assembler build steps and update self-hosting:

```bash
# Build asm23 instruction table generator and instruction table
(cd 23 && mkdir -p out &&
  ../emulator.out ../22/out/asm_debug.out 2000 /dev/null /dev/null instgen.asm out/instgen.out &&
  ../emulator.out out/instgen.out 2000 /dev/null out/inst.asm.out &&
  ../emulator.out ../22/out/asm_debug.out 2000 /dev/null /dev/null asm.asm out/asm.out &&
  ../emulator.out ../22/out/asm_debug.out 2000 /dev/null /dev/null asm.asm out/asm_debug.out define:enable_debug)

# Self-hosting check
(cd 23 && ../emulator.out out/asm.out 2000 /dev/null /dev/null asm.asm out/asm_2.out)
diff <(hexdump -C 23/out/asm.out) <(hexdump -C 23/out/asm_2.out)
```

Remove the self-hosting check for asm22 (only the latest version needs it).

### 3. Update Other Files

- **run_tests.py** - Update assembler path to `23/out/asm_debug.out`
- **gogen.sh** - Add new version's files to the watch list
- **asmtestgen.sh** - Update test program and file_stack_test to use new assembler

### 4. Build and Verify

```bash
./asmtestgen.sh       # Full build chain
./run_tests.py  # Test suite
```

### Checklist

- [ ] Version directory created with all source files
- [ ] `asmtestgen.sh` updated (build steps, self-hosting, test program)
- [ ] Previous version's self-hosting check removed
- [ ] `run_tests.py` assembler path updated
- [ ] `gogen.sh` watch list updated
- [ ] Build chain passes
- [ ] All tests pass
- [ ] README.md updated
