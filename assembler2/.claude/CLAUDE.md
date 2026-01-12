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

The build succeeds when `asm20.out == asm20_2.out` (self-assembly verification).

## Architecture

This is a self-hosting 6502 assembler built through progressive bootstrapping. The current assembler (`asm20.asm`) can assemble its own source code.

### Bootstrap Chain

External vasm assembles `asm4v.asm` → `asm4v.out`, which then assembles progressively more capable versions (`asm4b.asm` → `asm4b2.asm` → ... → `asm4b13.asm`). Each version adds features needed by the next.

### Key Components

- **Instruction generators** (`instgen*.asm`): Generate `inst*.asm.out` files containing pre-computed instruction hash tables. These are `.include`d by the assemblers to avoid runtime initialization.

- **Hash tables**: Used for both label lookup (`LHASHTAB` at $1F00) and instruction lookup (`IHASHTAB`). Hash entries are stored on a heap (`MEMPL/MEMPH`).

- **Two-pass assembly**: Pass 1 collects labels, Pass 2 resolves references and emits code.

### Memory Layout (asm20)

- `$0000-$00FF`: Zero page variables (see `.zeropage` section)
- `$1D00`: TOKEN buffer (current token being read)
- `$1E00`: Label hash table
- `$2000+`: Generated code
- `$F000`: File stack (grows downward)

### Shared Code Pattern

Common code is factored into include files:
- `common20.asm`: Shared between `asm20.asm` and `instgen20.asm`
- `hash_table20.asm`: Hash table implementation (included by common20)

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

### Expression Evaluation (asm19+)

Starting with asm19, the assembler supports simple expression evaluation with `+` and `-` operators:

**Syntax:**
- `LDA #$10+$20` - Arithmetic in immediate mode
- `foo = bar+$01` - Expressions in label assignments
- `.data value+$05` - Expressions in data directives
- `LDA (ptr+$02,X)` - Expressions in address operands
- `LDA #'Z'-'A'` - Character constant arithmetic

**Operator Precedence:**
- Evaluation is strictly **left-to-right**
- No operator precedence: `$10+$20-$05` evaluates as `($10+$20)-$05`
- No parentheses for grouping (except for addressing modes)

**Byte Selectors:**
- `<` (low byte) and `>` (high byte) apply to the **entire expression result**
- `LDA #<addr+$10` means `<(addr+$10)`, not `(<addr)+$10`
- Byte selectors work with any expression: `LDA #>'A'+$100`

**Value Types:**
- Hex constants: `$10`, `$ABCD`
- Character literals: `'A'`, `'\n'`, `'\''`
- Labels: `foo`, `bar`
- All three types can be mixed in expressions

**Forward References:**
- If any term in an expression is a forward reference, the entire expression is treated as a forward reference
- The assembler resolves the complete expression in pass 2

### Conditional Assembly (asm20+)

Starting with asm20, the assembler supports conditional assembly directives:

**Directives:**
- `.ifdef label` - Begin conditional block if label is defined
- `.endif` - End conditional block

**Usage:**
```asm
DEBUG = $01          ; Define a label

.ifdef DEBUG
  LDA #$42           ; This code is assembled
.endif

.ifdef UNDEFINED
  LDA #$FF           ; This code is skipped
.endif
```

**Nesting:**
- Conditional blocks can be nested arbitrarily deep
- Each `.ifdef` must have a matching `.endif`
- When a condition is false, nested conditionals are still parsed (for `.endif` matching) but their content is skipped

**Command Line Defines:**
- Labels can be pre-defined via command line: `define:label`
- Multiple defines are supported: `./asm20.out in out define:DEBUG define:FEATURE1`
- Pre-defined labels have value `$0001`

**Errors:**
- Error 23: `.endif without .ifdef` - Unmatched `.endif`
- Error 24: `Unclosed .ifdef` - Missing `.endif` at end of file
- Error 25: `Label expected` - `.ifdef` without a label name

## Migration Patterns

Lessons learned from syntax migrations (e.g., DATA → .data):

1. **Global replacements need context awareness** - Avoid blind find/replace when identifiers share common substrings (e.g., `DATA` vs `MODE_DATA`). Check for compound identifiers before replacing.

2. **File copying requires systematic include updates** - When creating a new version (asm18→asm19), all include references across all copied files need updating (asm, instgen, common, errors, fwdref, file_stack, hash_table, to_decimal).

3. **Phased migration works well** - Add new feature alongside old, verify everything works, then remove old. This provides safety checkpoints at each phase.

4. **Self-hosting is powerful verification** - The assembler assembling itself catches subtle issues that unit tests might miss. Always run the full build chain after changes.

5. **Test suite retention is valuable** - Keep the old test suite (e.g., asm18_tests.txt) as reference even when removing obsolete tests from the new one (asm19_tests.txt).
