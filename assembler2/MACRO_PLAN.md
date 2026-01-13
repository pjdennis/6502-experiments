# Implementation Plan: Macro Feature

## Overview

Add macro support with the following capabilities:
- `.macro NAME [param1 param2 ...]` / `.endmacro` directives
- Local labels scoped per expansion
- Parameter substitution with forward ref propagation
- Error tracebacks showing expansion context
- No recursion (error if attempted)
- Macros can be defined inside `.ifdef` blocks

## Syntax Example

```asm
; Macro definition
  .macro INC16 addr
    INC addr
    BNE .done
    INC addr+$01
.done:
  .endmacro

; Macro usage
my_func:
  INC16 var1
  BNE .done
  INC16 var2
.done:
```

## Key Design Decisions

### Macro Name Storage
- Use IHASHTAB (instruction hash table) with `$FE` sentinel byte to distinguish macros
- Error if macro name shadows an existing instruction
- Single lookup for opcode position (efficient)

### Macro Body Storage
- Store on heap (same as labels)
- Format: lines terminated by `$0A`, with the definition terminated by single `$00`

### Label Scoping
- Each macro expansion gets its own scope via expansion ID
- Push/pop scope mechanism (similar to file stack pattern)
- 2-byte expansion counter allows >256 expansions

### Macro Expansion
- Extend file_stack to handle memory sources (macro bodies)
- `read_char` dispatches based on source type (file vs macro)

### Parameter Substitution
- Value substitution: parameters stored in local scope with evaluated values
- **Pass 1:** Only create parameter if argument is NOT a forward reference
- **Pass 2:** Always create parameter (all labels resolved.) If parameter already exists from pass 1 it does not need to be added; can be skipped.
- This preserves zero-page optimization for known values
- Forward refs in arguments naturally become forward refs in macro body
- Parameters stored as 2-byte values (same as labels, no size flag needed)
- Addressing mode inferred from value: ≤$FF uses zero-page, >$FF uses absolute
- In `.data` directives, parameters emit 2 bytes (like labels); use `<param` for 1 byte. This should not need any special new logic.

### Two-Pass Behavior
- Pass 1: Expand macros for label collection, skip fwdref parameters
- Pass 2: Expand macros with all parameters populated
- Scope counter is reset after Pass 1 so that scopes match during pass 2 allowing resolution of forward references within macros.

### Recursion
- Disallowed - error if macro attempts to invoke itself

### Error Reporting
- Full traceback showing include stack and macro expansion context
- Macro errors show: macro name + line number relative to definition

---

## Phase 0: Pre-refactoring

### 0A: Error Traceback for Includes

**Goal:** Show full include stack in error messages.

**Current behavior:**
```
Error: Label not found at line 15
```

**New behavior:**
```
Error: Label not found
  at include2.asm:15
  included from include1.asm:42
  included from main.asm:10
```

**Changes:**
1. Modify error reporting to walk the file stack
2. For each stack entry, print filename and line number
3. Filename already stored in file stack entries

**Files:** `asm21.asm` (error routines), `file_stack21.asm`

**Tests:**
- Error in included file shows traceback
- Nested includes show full chain
- Error in main file (no includes) works as before

**Commit point:** After tests pass

---

### 0B: Generalize Source Stack for Memory Sources

**Goal:** File stack can handle both files and memory buffers (for macro bodies).

**Changes:**
1. Add source type byte to stack entries: `$00` = file, `$FF` = macro
2. For macro entries, store body pointer and read position
3. Add `MACRO_READ_PTR_L/H` zero-page variables
4. Modify `read_char` to dispatch based on source type
5. Add `push_macro_source` / corresponding pop logic

**Stack entry format:**
```
File:  [filename $00][prev_handle 1B][prev_line 2B][type=$00]
Macro: [macro_name $00][prev_handle 1B][prev_line 2B][type=$FF][body_ptr 2B][read_ptr 2B][macro_line 2B]
```

**Files:** `file_stack21.asm`, `asm21.asm`

**Tests:**
- Existing include tests still pass
- (Macro-specific tests come in Phase 2)

**Commit point:** After tests pass

---

### 0C: Scope Stack for Local Labels

**Goal:** Push/pop label scope for macro expansions.

**Changes:**
1. Add `EXPANSION_ID_L/H` (2-byte counter for unique scope IDs)
2. Add `push_label_scope`:
   - Save `CURR_GLOBAL_HEAP_L/H` and `CACHED_HASH`
   - Increment `EXPANSION_ID`
   - Set up synthetic scope using expansion ID as hash seed
3. Add `pop_label_scope`:
   - Restore saved values
4. Local labels within macro hash against expansion ID
5. Reset `EXPANSION_ID` to 0 between passes:
   - Ensures pass 2 uses same scope IDs as pass 1
   - Local labels and parameters from pass 1 are found in pass 2
   - Forward refs within macros resolve correctly

**Files:** `asm21.asm`, `hash_table21.asm`

**Tests:**
- Tested with macro expansion in Phase 2

**Commit point:** With Phase 2

---

## Phase 1: Macro Definition Capture

### 1A: Parse `.macro` Directive

**Goal:** Parse macro definition header, prepare to capture body.

**Changes:**
1. Add `.macro` and `.endmacro` to directive list
2. Parse: `.macro NAME [param1 param2 ...]`
3. Verify macro name doesn't shadow an instruction (error if so)
4. Verify macro not already defined (error if so - like duplicate label)
5. Create entry in IHASHTAB:
   ```
   [name $00][$FE][body_ptr_L][body_ptr_H][param_count][param1 $00][param2 $00]...
   ```
6. Enter "capturing" mode

**New zero-page variables:**
```
IN_MACRO_DEF      ; Flag: currently capturing macro body
MACRO_DEF_PTR_L   ; Heap pointer where body is being stored
MACRO_DEF_PTR_H
MACRO_PARAM_COUNT ; Number of parameters
```

**Files:** `asm21.asm`

**Tests:**
- Simple macro definition (no params) parses without error
- Macro with 1 parameter parses correctly
- Macro with multiple parameters parses correctly
- Duplicate macro definition -> error
- Macro shadowing instruction (e.g., `.macro LDA`) -> error
- `.endmacro` without `.macro` -> error

**Commit point:** After tests pass

---

### 1B: Capture Macro Body

**Goal:** Store macro body on heap during definition.

**Changes:**
1. While `IN_MACRO_DEF` is set:
   - Copy source lines to heap (preserving `$0A` line terminators)
   - Don't process as normal assembly
2. On `.endmacro`:
   - Write `$00` terminator
   - Clear `IN_MACRO_DEF`
   - Finalize macro entry (body_ptr now points to complete body)
3. Handle `.macro` inside `.ifdef` (only capture if not skipping)

**Tests:**
- Macro body with instructions captures correctly
- Macro body with local labels captures correctly
- Macro body with directives captures correctly
- Content after `.endmacro` processes normally
- Unclosed macro (EOF before `.endmacro`) -> error
- Macro inside `.ifdef` (true condition) works
- Macro inside `.ifdef` (false condition) skipped entirely

**Commit point:** After tests pass

---

## Phase 2: Macro Expansion (No Parameters)

### 2A: Detect Macro Invocation

**Goal:** Recognize macro name in opcode position.

**Changes:**
1. In `lookup_mnemonic`, after `find_in_hash_instruction`:
   - Check if first value byte is `$FE` (macro sentinel)
   - If yes: extract body pointer, branch to expansion
   - If no: continue with normal instruction processing

**Files:** `asm21.asm`

**Tests:**
- Parameterless macro invoked, body executes
- Macro with just `NOP` generates correct byte

**Commit point:** After tests pass

---

### 2B: Macro Expansion with Scoping

**Goal:** Expand macro body with proper local label isolation.

**Changes:**
1. Check for recursion:
   - Walk source stack, check if same macro already expanding
   - If yes -> error
2. Push source stack (macro body as memory source)
3. Push label scope (new expansion ID)
4. Process macro body via normal line loop
5. On body exhaustion (`$00` terminator):
   - Pop source stack
   - Pop label scope

**Tests:**
- Macro with local label works correctly
- Same local label name in macro and caller don't conflict
- Two invocations of same macro have independent local labels
- Macro invoking different macro works (if we want to allow this)
- Recursive macro invocation -> error
- Macro generating branch to its own local label works

**Commit point:** After tests pass

---

### 2C: Error Reporting with Macro Context

**Goal:** Errors show macro expansion context.

**Changes:**
1. Error traceback includes macro expansions
2. Format: `in macro NAME line N` (line relative to macro start)
3. Track line number within macro body during expansion
4. Full traceback example:
   ```
   Error: Label not found
     in macro INC16 line 3
     expanded at program.asm:50
     included from main.asm:10
   ```

**Tests:**
- Error in macro body shows macro name and relative line
- Error in macro in included file shows full chain

**Commit point:** After tests pass

---

## Phase 3: Parameters

### 3A: Parse Arguments at Invocation

**Goal:** Parse argument values when macro is invoked.

**Changes:**
1. After detecting macro invocation, get parameter count from entry
2. For each expected parameter:
   - Parse argument expression (`parse_expression`)
   - Store: value (2 bytes) + forward ref flag (1 byte)
3. Verify argument count matches parameter count:
   - Too few -> error
   - Too many -> error
4. Store arguments in temporary area for scope population

**Temporary argument storage:** Small array, e.g., 8 entries max:
```
MACRO_ARGS: [val_L][val_H][is_fwdref] × 8
```
Or dynamic based on param count. The `is_fwdref` byte is only needed during argument parsing to decide whether to populate the parameter in pass 1.

**Tests:**
- Correct number of arguments accepted
- Too few arguments -> error
- Too many arguments -> error
- Zero arguments for parameterless macro works

**Commit point:** After tests pass

---

### 3B: Populate Parameters in Scope

**Goal:** Add parameter values to macro's local scope.

**Changes:**
1. At expansion start, for each parameter:
   - Get parameter name from macro definition
   - Get argument value from parsed arguments
   - Check forward ref flag from parsing
   - **Pass 1:** Only add to scope if argument was NOT forward ref
   - **Pass 2:** Check if parameter already exists in scope (from pass 1):
     - If exists: skip (already has correct value)
     - If not exists: add now (was fwdref in pass 1, now resolved)
2. Add to local scope same as local labels (2-byte value, no size flag)
3. Since `EXPANSION_ID` is reset between passes, scope IDs match:
   - Pass 1 and pass 2 use same scope for same expansion
   - Parameters/labels from pass 1 are found in pass 2
4. Parameters behave exactly like labels:
   - In instruction operands: addressing mode inferred from value (≤$FF → zero-page)
   - In `.data` directives: emits 2 bytes; use `<param` for 1 byte

**Tests:**
- `INC16 $80` - uses zero-page mode (value ≤$FF)
- `INC16 $1234` - uses absolute mode (value >$FF)
- `INC16 zp_var` where zp_var=$50 - uses zero-page mode
- Parameter in expression: `addr+$01` evaluates correctly
- Multiple parameters work independently
- Parameter shadows same-named global label (parameter wins in macro scope)
- `.data addr` emits 2 bytes; `.data <addr` emits 1 byte

**Commit point:** After tests pass

---

### 3C: Forward Reference Propagation

**Goal:** Forward ref arguments become forward refs in macro body.

**Changes:**
1. Pass 1 behavior when argument is forward ref:
   - Don't add parameter to scope
   - In macro body, parameter name lookup fails
   - Treated as forward reference (existing mechanism)
   - Forces absolute addressing (standard fwdref behavior)
2. Pass 2 behavior:
   - `EXPANSION_ID` was reset, so same scope ID as pass 1
   - Parameter didn't exist in pass 1, so add it now with resolved value
   - Lookup succeeds, addressing mode based on resolved value
3. This works because:
   - Scope IDs match between passes (counter reset)
   - Parameter lookup in pass 2 finds entry added in pass 2
   - No conflict with pass 1 since parameter wasn't added then

**Tests:**
- Forward ref argument -> absolute addressing in pass 1
- Forward ref resolving to zero-page value ($00-$FF) uses zero-page in pass 2
- Forward ref resolving to absolute value (>$FF) uses absolute in pass 2
- Mix of resolved and forward ref arguments in same invocation
- Forward ref local label within macro resolves correctly

**Commit point:** After tests pass

---

## Phase 4: Polish and Edge Cases

**Goal:** Handle remaining edge cases and improve robustness.

**Tests to add:**
- Empty macro body (just `.macro` / `.endmacro`) works
- Macro with only comments works
- Macro with only local labels works
- Very long macro body (heap space permitting)
- Many macro invocations (expansion counter doesn't overflow for reasonable use)
- Macro defined and used in same file
- Macro defined in include, used in main file
- Macro defined in include, used in different include
- Macro invocation as only content on line
- Macro invocation with comment after arguments
- Whitespace variations in macro definition and invocation

**Commit point:** After all tests pass

---

## File Changes Summary

| File | Changes |
|------|---------|
| `asm21.asm` | Directives, expansion logic, error reporting, scope management |
| `file_stack21.asm` | Memory source support, type flag |
| `hash_table21.asm` | Scope push/pop, parameter entries with size flag |
| `tests/asm21_tests.txt` | Many new tests |

---

## Memory Layout

```
$0200-$03FF: FWDREF_LIST (512 bytes)
$1D00-$1DFF: TOKEN (256 bytes)
$1E00-$1EFF: LHASHTAB (256 bytes) - labels
$1F00-$1FFF: IHASHTAB (256 bytes) - instructions AND macros
$2000+:      Code, then heap grows upward
$F000:       Source stack (grows downward)
```

No new hash table needed - macros share IHASHTAB with `$FE` sentinel.

---

## New Zero-Page Variables

```asm
; Macro definition
IN_MACRO_DEF      .data $00  ; Flag: capturing macro body
MACRO_DEF_PTR_L   .data $00  ; Heap pointer for body storage
MACRO_DEF_PTR_H   .data $00

; Macro expansion
EXPANSION_ID_L    .data $00  ; 2-byte expansion counter
EXPANSION_ID_H    .data $00
MACRO_READ_PTR_L  .data $00  ; Read position in macro body
MACRO_READ_PTR_H  .data $00
MACRO_LINE_L      .data $00  ; Line number within macro (for errors)
MACRO_LINE_H      .data $00

; Source stack
SOURCE_TYPE       .data $00  ; Current source: $00=file, $FF=macro
```

---

## Test Categories

### Definition Tests
- `macro_def_simple` - no params
- `macro_def_one_param`
- `macro_def_multi_param`
- `macro_def_duplicate` - error
- `macro_def_shadows_instruction` - error
- `macro_def_unclosed` - error
- `macro_endmacro_without_macro` - error
- `macro_def_in_ifdef_true`
- `macro_def_in_ifdef_false`

### Expansion Tests (No Params)
- `macro_expand_simple`
- `macro_expand_local_label`
- `macro_expand_local_no_conflict`
- `macro_expand_twice_independent`
- `macro_expand_recursive` - error
- `macro_expand_in_ifdef`

### Parameter Tests
- `macro_param_zeropage_value` - arg ≤$FF uses zero-page addressing
- `macro_param_absolute_value` - arg >$FF uses absolute addressing
- `macro_param_zeropage_label` - label with small value uses zero-page
- `macro_param_expression` - `addr+$01` works correctly
- `macro_param_low_byte` - `<arg` extracts low byte
- `macro_param_high_byte` - `>arg` extracts high byte
- `macro_param_wrong_count` - error
- `macro_param_fwdref` - forward ref forces absolute, resolves in pass 2
- `macro_param_fwdref_zp` - forward ref to zp value uses zp in pass 2
- `macro_param_multiple` - multiple params work independently
- `macro_param_data_directive` - `.data param` emits 2 bytes
- `macro_param_data_low_byte` - `.data <param` emits 1 byte

### Error Reporting Tests
- `macro_error_traceback`
- `macro_error_in_include`
- `include_error_traceback` (Phase 0A)

---

## Risks and Mitigations

1. **Heap overflow with large macro bodies**
   - Mitigation: Check heap space before storing, error if insufficient

2. **Expansion counter overflow**
   - Mitigation: 2-byte counter allows 65536 expansions, sufficient for practical use

3. **Deep nesting of includes + macros**
   - Mitigation: Source stack has finite space, will naturally limit depth

4. **Hash collisions between macro names and instructions**
   - Mitigation: Check for collision at definition time, error if shadows instruction
