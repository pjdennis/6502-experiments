# Plan: Optimize Macro Capture

## Goal
Optimize captured macro body text during `.macro` definition to reduce heap usage and speed up macro expansion:
- Multiple spaces → single space
- Strip comments (`;` to end of line)
- Remove trailing spaces
- Keep blank lines (preserve line numbering for error messages)
- Preserve content inside string (`"..."`) and character (`'...'`) constants

---

## Current Implementation

**Location:** `capture_macro_line` in asm22.asm (lines 1866-1969)

**Current behavior:** Copies raw characters verbatim from input to heap:
```asm
.cml_copy_loop
  STA (MEMP16),Y          ; Store byte at heap+Y
  CMP #'\n'
  BEQ .cml_line_done
  INY
  JSR read_char
  BCC .cml_copy_loop
```

**Problem:** Stores comments, redundant spaces, and trailing whitespace unnecessarily.

---

## Design

### State Machine Approach

Track parsing state with a single byte variable:
- `$00` = Normal mode (outside quotes)
- `$01` = In double-quoted string (`"..."`)
- `$02` = In character literal (`'...'`)
- `$80` = Escape pending (high bit set, combine with above)

### Processing Logic

For each input character:

**Normal mode ($00):**
| Input | Action |
|-------|--------|
| `"` | Store char, switch to string mode ($01) |
| `'` | Store char, switch to char mode ($02) |
| `;` | Skip to newline (comment), emit `\n`, done |
| `\n` | Emit `\n` (trim trailing space already handled), done |
| space after space | Skip (don't store) |
| other | Store char |

**String mode ($01):**
| Input | Action |
|-------|--------|
| `\` | Store char, set escape flag ($81) |
| `"` | Store char, switch to normal mode ($00) |
| `\n` | Store char, switch to normal mode (unterminated string - let expansion catch error) |
| other | Store char |

**Char mode ($02):**
| Input | Action |
|-------|--------|
| `\` | Store char, set escape flag ($82) |
| `'` | Store char, switch to normal mode ($00) |
| `\n` | Store char, switch to normal mode (unterminated char - let expansion catch error) |
| other | Store char |

**Escape mode ($8x):**
| Input | Action |
|-------|--------|
| any | Store char, clear escape flag (back to $01 or $02) |

### Consecutive Space Handling

Simple approach - track "previous was space" flag:
- When space encountered: if flag set, skip; otherwise store space and set flag
- When non-space encountered: clear flag, store char
- A single trailing space before newline is acceptable

### Blank Line Preservation

A line that becomes blank (all spaces/comment only) still emits a newline. This preserves line count for error reporting during expansion.

---

## Step 0: Debug Macro Display

Before implementing optimization, add a `show_macros` debug feature to help verify the optimization is working correctly.

### New Zero-Page Variable

```asm
SHOW_MACROS     .data $00   ; Flag: print macro definitions to stderr
```

### Command Line Argument

Add parsing for `show_macros` argument (similar to existing `define:` handling):
- Check for "show_macros" string after filename arguments
- Set `SHOW_MACROS` flag to $FF if present

### Display Logic

At end of `process_endmacro` (after body is complete), if `SHOW_MACROS` is set:

1. Print "Macro: " followed by macro name (from TOKEN buffer or saved location)
2. Print "Params: " followed by parameter list (walk heap from param start to first $00)
3. Print "Body:" followed by newline
4. Print captured body (walk heap from body start to terminating $00)
5. Print blank line separator

Output goes to stderr via `write_char_error` (address $F00C).

### Files to Modify (Step 0)

- **asm22.asm**: Add SHOW_MACROS variable, argument parsing, display logic in process_endmacro

---

## Step 1: Macro Capture Optimization

### New Zero-Page Variables

Add to `.zeropage` section in asm22.asm:
```asm
CAPTURE_STATE   .data $00   ; Macro capture state machine
PREV_WAS_SPACE  .data $00   ; Flag: previous stored char was space
```

### Modified capture_macro_line

Replace the simple copy loop with optimizing logic. Keep the existing structure but add state-based processing:

```asm
capture_macro_line:
  BIT PASS
  BMI .cml_pass2           ; Pass 2: skip lines (unchanged)

  ; --- Pass 1: Capture with optimization ---
  LDY #$00
  STY CAPTURE_STATE        ; Start in normal mode
  STY PREV_WAS_SPACE       ; No previous space
  JSR read_char
  BCS .cml_eof

.cml_process_char:
  ; Check state and branch accordingly
  LDX CAPTURE_STATE
  BMI .cml_escape_mode     ; High bit set = escape pending
  BNE .cml_quoted_mode     ; Non-zero = in quotes

  ; --- Normal mode ---
  CMP #'"'
  BEQ .cml_start_string
  CMP #'\''
  BEQ .cml_start_char
  CMP #';'
  BEQ .cml_comment         ; Skip rest of line
  CMP #'\n'
  BEQ .cml_end_line
  CMP #' '
  BEQ .cml_space
  ; Other character - store it, clear space flag
  JSR .cml_store_char
  LDA #$00
  STA PREV_WAS_SPACE
  JMP .cml_next_char

.cml_space:
  ; If previous was space, skip this one
  LDA PREV_WAS_SPACE
  BNE .cml_next_char       ; Skip consecutive space
  LDA #$FF
  STA PREV_WAS_SPACE
  LDA #' '
  JSR .cml_store_char
  JMP .cml_next_char

.cml_comment:
  ; Skip to newline, then emit newline
.cml_skip_comment:
  JSR read_char
  BCS .cml_eof
  CMP #'\n'
  BNE .cml_skip_comment
  ; Fall through to end_line

.cml_end_line:
  ; Reset space flag, emit newline
  LDA #$00
  STA PREV_WAS_SPACE
  LDA #'\n'
  JSR .cml_store_char
  ; ... (rest similar to existing: check for .endmacro, advance heap)

.cml_start_string:
  LDA #$00
  STA PREV_WAS_SPACE       ; Clear space flag
  LDA #$01
  STA CAPTURE_STATE
  LDA #'"'
  JSR .cml_store_char
  JMP .cml_next_char

.cml_start_char:
  LDA #$00
  STA PREV_WAS_SPACE       ; Clear space flag
  LDA #$02
  STA CAPTURE_STATE
  LDA #'\''
  JSR .cml_store_char
  JMP .cml_next_char

.cml_quoted_mode:
  ; X contains state ($01 or $02)
  ; Inside quotes - store everything verbatim
  CMP #'\'
  BEQ .cml_escape
  CPX #$01
  BEQ .cml_check_dquote
  ; Char mode - check for closing '
  CMP #'\''
  BEQ .cml_end_quote
  BNE .cml_store_quoted
.cml_check_dquote:
  CMP #'"'
  BEQ .cml_end_quote
.cml_store_quoted:
  CMP #'\n'
  BEQ .cml_end_quote_newline
  JSR .cml_store_char
  JMP .cml_next_char

.cml_escape:
  ; Set escape flag (high bit)
  TXA
  ORA #$80
  STA CAPTURE_STATE
  LDA #'\'
  JSR .cml_store_char
  JMP .cml_next_char

.cml_escape_mode:
  ; Store escaped char, clear escape flag
  JSR .cml_store_char
  TXA
  AND #$7F                 ; Clear high bit
  STA CAPTURE_STATE
  JMP .cml_next_char

.cml_end_quote:
  JSR .cml_store_char
  LDA #$00
  STA CAPTURE_STATE        ; Back to normal mode
  JMP .cml_next_char

.cml_end_quote_newline:
  ; Unterminated quote - store newline, reset state
  ; Let expansion report the error
  LDA #$00
  STA CAPTURE_STATE
  LDA #'\n'
  JSR .cml_store_char
  JMP .cml_line_done       ; Treat as end of line

.cml_store_char:
  STA (MEMP16),Y
  INY
  BPL .cml_store_done
  JSR advance_heap         ; Y hit 128
.cml_store_done:
  RTS

.cml_next_char:
  JSR read_char
  BCS .cml_eof
  JMP .cml_process_char
```

### Code Reuse

- Reuse existing `advance_heap` for heap management
- Reuse existing `.endmacro` detection logic (unchanged)
- State machine is new but follows patterns from existing `parse_char_literal`

---

## Files to Modify

### Step 0
1. **asm22.asm**
   - Add `SHOW_MACROS` zero-page variable
   - Add command-line argument parsing for "show_macros"
   - Add display logic in `process_endmacro`

### Step 1
1. **asm22.asm**
   - Add `CAPTURE_STATE` and `PREV_WAS_SPACE` zero-page variables
   - Replace `capture_macro_line` pass 1 logic with optimizing version
   - Keep pass 2 logic unchanged (just skips lines)

---

## Test Strategy

### New Tests (tests/asm22_tests.txt)

```
---
NAME: macro_capture_strips_comments
DESCRIPTION: Comments stripped from macro body
INPUT:
 1: * = $0200
 2:   .macro TEST
 3:   NOP ; this comment should be stripped
 4:   .endmacro
 5:   TEST
EXPECT_HEX: ea

---
NAME: macro_capture_compresses_spaces
DESCRIPTION: Multiple spaces compressed in macro body
INPUT:
 1: * = $0200
 2:   .macro TEST
 3:   LDA    #$42
 4:   .endmacro
 5:   TEST
EXPECT_HEX: a9 42

---
NAME: macro_capture_preserves_string_spaces
DESCRIPTION: Spaces in strings preserved
INPUT:
 1: * = $0200
 2:   .macro TEST
 3:   .data "a  b"
 4:   .endmacro
 5:   TEST
EXPECT_HEX: 61 20 20 62

---
NAME: macro_capture_preserves_string_semicolon
DESCRIPTION: Semicolon in string not treated as comment
INPUT:
 1: * = $0200
 2:   .macro TEST
 3:   .data "a;b"
 4:   .endmacro
 5:   TEST
EXPECT_HEX: 61 3b 62

---
NAME: macro_capture_preserves_char_literal
DESCRIPTION: Char literals preserved correctly
INPUT:
 1: * = $0200
 2:   .macro TEST
 3:   LDA #' '
 4:   .endmacro
 5:   TEST
EXPECT_HEX: a9 20

---
NAME: macro_capture_preserves_line_numbers
DESCRIPTION: Blank lines preserved for error line numbers
INPUT:
 1: * = $0200
 2:   .macro TEST
 3:   NOP
 4:   ; comment-only line becomes blank
 5:
 6:   UNDEFINED_LABEL
 7:   .endmacro
 8:   TEST
EXPECT_ERROR: 1
EXPECT_LINE: 6
EXPECT_MSG: Label not found

---
NAME: macro_capture_string_with_escape
DESCRIPTION: Escape sequences in strings preserved
INPUT:
 1: * = $0200
 2:   .macro TEST
 3:   .data "a\nb"
 4:   .endmacro
 5:   TEST
EXPECT_HEX: 61 0a 62

---
NAME: macro_capture_char_escape
DESCRIPTION: Escape sequences in char literals preserved
INPUT:
 1: * = $0200
 2:   .macro TEST
 3:   LDA #'\''
 4:   .endmacro
 5:   TEST
EXPECT_HEX: a9 27
```

---

## Verification

### Step 0 Verification
1. Run build: `./asmtestgen.sh`
2. Test show_macros manually:
   ```bash
   ./emulator.out out/asm22_debug.out 2000 test.asm /dev/null show_macros
   ```
3. Verify macro name, params, and body print to stderr

### Step 1 Verification
1. Run full build: `./asmtestgen.sh`
2. Run test suite: `./tests/run_tests.py`
3. Verify self-assembly still succeeds (asm22.out == asm22_2.out)
4. Check new tests pass
5. Use show_macros to verify optimization is working:
   - Comments stripped
   - Multiple spaces compressed
   - Strings/chars preserved

---

## Considerations

### Performance
The state machine adds branching overhead per character. However:
- Macros are typically small
- Reduced heap usage improves memory efficiency
- Smaller stored bodies = faster expansion (less to re-read)

### Edge Cases
- Unterminated strings/chars: Let expansion report error (preserve newline, reset state)
- Tab characters: Preserved as-is (tabs not currently supported by assembler)
- Nested quotes in strings: Handled by escape sequences (`\"` or `\'`)

### Future Enhancements
- Could also strip leading whitespace (optional)
- Could convert tabs to spaces
- Could track and report macro body size reduction for debugging
