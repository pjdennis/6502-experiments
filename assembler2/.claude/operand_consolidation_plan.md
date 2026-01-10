# Plan: Consolidate Operand Value Parsing

## Status: READY - Accumulator syntax migration complete

The accumulator syntax side quest is complete (commits fe7035c, e8e2e8d, 59cfac4).
Ready to proceed with operand consolidation.

---

## Phase 1 Findings: Forward Reference Handling in asm19

**Line numbers current as of commit 59cfac4 (after accumulator syntax removal)**

### Current Forward Reference Mechanism

#### Key Functions

1. **`read_and_find_existing_label`** (line 277)
   - Used when parsing `<label` or `>label` (with operators)
   - If label not found in pass 1: sets HEX1=HEX2=$00, returns normally (no error)
   - If label not found in pass 2: jumps to err_label_not_found
   - **Does NOT set IS_FWDREF flag**

2. **`.is_label` section** (lines 1391-1425)
   - Used when parsing bare labels (no < or > prefix)
   - Reads token with `JSR read_token` (line 1393)
   - Looks up label via `check_local_label` + `select_label_hash_table` + `find_in_hash` (lines 1396-1398)
   - If not found in pass 1:
     - Sets IS_FWDREF = $FF (line 1405)
     - Sets HEX1=HEX2=$00 (lines 1407-1408)
   - If found:
     - Sets IS_FWDREF = $00 (line 1415)
   - Stores result in OPERAND_L/H (lines 1418-1421)
   - **This is the ONLY place IS_FWDREF is set**

3. **`handle_fwdref_mode`** (line 1533)
   - Called ONLY for ZP/ZPX/ZPY mode selection (lines 1447, 1467, 1487)
   - In pass 1 with forward ref: calls add_forward_ref, returns C=1 (use ABS)
   - In pass 2: calls check_forward_ref to see if PC is in list
   - Purpose: Forces absolute addressing for forward refs (can't know if <= $FF in pass 1)

#### Where Forward Reference Tracking Happens

**Forward refs are ONLY tracked for bare labels in ZP-capable contexts:**

- `label` (non-indexed) - around lines 1477-1495; calls handle_fwdref_mode at line 1487
  - If value <= $FF and ZP mode exists and not forward ref → use ZP
  - Otherwise → use ABS

- `label,X` (X-indexed) - around lines 1437-1455; calls handle_fwdref_mode at line 1447
  - If value <= $FF and ZPX mode exists and not forward ref → use ZPX
  - Otherwise → use ABSX

- `label,Y` (Y-indexed) - around lines 1457-1475; calls handle_fwdref_mode at line 1467
  - If value <= $FF and ZPY mode exists and not forward ref → use ABSY
  - Otherwise → use ABSY

**Forward refs are NOT tracked for:**
- `#<label`, `#>label` - immediate mode (lines 1067-1092)
- `<label`, `>label` - .data directive (lines 1567-1578)
- Any context where operators explicitly extract byte

#### Why Operators Bypass Tracking

When `<` or `>` is used:
1. Uses `read_and_find_existing_label` (not `.is_label`)
2. IS_FWDREF flag is never set
3. No call to `handle_fwdref_mode`
4. Result: Always uses the specified byte, no ZP/ABS optimization

This makes sense because:
- `#<label` - user explicitly requested low byte
- `#>label` - user explicitly requested high byte
- No ambiguity about addressing mode

### Implications for parse_value Function

#### Design Requirements

The `parse_value` function must distinguish between:

1. **Bare label** → needs forward ref tracking
   - Set IS_FWDREF flag based on lookup result
   - Return C=1 to signal "undecorated label"
   - Caller will call handle_fwdref_mode if doing ZP selection

2. **Operator-prefixed label** (`<label` or `>label`) → NO tracking
   - Use read_and_find_existing_label (current behavior)
   - Return C=0 to signal "decorated label"
   - Caller skips handle_fwdref_mode

3. **Hex value** (`$12` or `$1234`) → NO tracking
   - Use read_hex_byte_or_word
   - Return C=0
   - Caller skips handle_fwdref_mode

#### Proposed Interface

```asm
; Parse a value: $12, $1234, label, <label, or >label
; On entry: A contains first character
; On exit:  A contains next character
;           OPERAND_L, OPERAND_H contain parsed value
;           IS_FWDREF set if bare label was forward ref (pass 1 only)
;           C=1 if bare label, C=0 otherwise
;           X, Y preserved
```

The C flag tells caller whether to call `handle_fwdref_mode`.

---

## Phase 2: Add Comprehensive Test Coverage (30 min)

Add tests for currently restricted combinations that will now be allowed:

### New Positive Tests
- [ ] `LDA label` (absolute with label, currently works)
- [ ] `LDA <label` (force ZP with label)
- [ ] `LDA >label` (high byte in absolute)
- [ ] `LDA $1234,X` (absolute indexed with word)
- [ ] `LDA label,X` (absolute indexed with label)
- [ ] `LDA ($1234)` (indirect absolute - JMP only)
- [ ] `STA ($12),Y` (indirect indexed with hex)
- [ ] Forward reference variations

### New Negative Tests
- [ ] `LDA #$1234` (immediate with word - already added)
- [ ] `LDA $1234` where value is used as ZP (catches at emit)
- [ ] `LDA ($1234),Y` (indirect indexed needs ZP, emit should catch)

---

## Phase 3: Design and Implement `parse_value` (30 min)

### Function Structure

```asm
parse_value
  CMP #'$'
  BEQ .hex
  CMP #'<'
  BEQ .low_byte
  CMP #'>'
  BEQ .high_byte
  ; Otherwise: bare label - needs forward ref tracking
  ; Save TOKEN state, read token, lookup in hash
  ; Set IS_FWDREF based on result
  ; Return C=1
  ...
.hex
  JSR read_char
  JSR read_hex_byte_or_word
  ; Store in OPERAND_L/H
  ; Return C=0
  ...
.low_byte
  JSR read_char
  JSR read_and_find_existing_label
  ; Store HEX2 in OPERAND_L, $00 in OPERAND_H
  ; Return C=0
  ...
.high_byte
  JSR read_char
  JSR read_and_find_existing_label
  ; Store HEX1 in OPERAND_L, $00 in OPERAND_H
  ; Return C=0
  ...
```

---

## Phase 4: Incremental Refactoring (2 hours)

Refactor one addressing mode at a time, testing after each:

1. Absolute Mode (non-indexed) - simplest case
2. Immediate Mode (except char literals)
3. Absolute Indexed (X and Y)
4. Zero Page Modes
5. Indirect Modes
6. Branch/Relative Mode

---

## Phase 5: Cleanup (20 min)

- Remove dead code
- Update comments
- Final testing

---

## Success Criteria
1. Single `parse_value` function handles all value parsing
2. Uniform syntax: `$12`, `$1234`, `label`, `<label`, `>label` work everywhere
3. Validation happens at emit time
4. Forward reference handling preserved
5. All tests pass
6. ~100-200 lines of duplicate code removed

## Estimated Time: 3-4 hours
