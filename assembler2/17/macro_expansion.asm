; macro_expansion.asm - Macro invocation and expansion
;
; Provides: check_macro_recursion, expand_macro
;
; Requires:
;   CURR_CHAR (asm.asm alias; backing storage in source_stack.asm)
;   TOKEN, PASS (asm.asm)
;   IN_MACRO_DEF (macro_capture.asm)
;   MACRO_ACTIVATION, MACRO_ACTIVATION_LIMIT, MACRO_ENTRY16, OPERAND16,
;   TEMP (asm.asm)
;   LABEL_SCOPE16, CACHED_HASH, scramble_table (hash_table.asm)
;   EXPANSION_ID16, SCOPE_DEPTH, MACRO_LOOKUP_FRAME16 (label_scope.asm)
;   read_char (asm.asm alias; implemented in source_stack.asm)
;   check_for_end_of_line (tokenizer.asm)
;   parse_expression (expressions.asm)
;   select_label_hash_table (common.asm)
;   hash_add (hash_table.asm), store_hash_value (common.asm)
;   push_memory_source_with_payload, ss_walk_frames_by_type,
;     SS_PAYLOAD16, SS_SRC_TYPE_MEMORY (source_stack.asm)
;   err_* (errors.asm)

  .code


; Check if the active macro is already being expanded somewhere up the
; source-stack chain. Walks every memory frame on the source stack via
; ss_walk_frames_by_type and compares each one's saved MACRO_ENTRY16
; against the active one. The saved entry is the last 2 bytes of each
; frame's payload region (set by expand_macro before push). Walking
; ignores file frames (file frames don't carry macro state).
;
; On entry: MACRO_ENTRY16 = the macro's hash table entry address.
; On exit:  Returns normally if no recursion; jumps to err_recursive_macro
;           on match. TABP16, A, Y clobbered; X preserved (matches the
;           legacy contract -- expand_macro relies on it).
check_macro_recursion:
  TXA
  PHA                           ; ss_walk_frames_by_type clobbers X
  LDA #<recursion_check_callback
  LDX #>recursion_check_callback
  LDY #SS_SRC_TYPE_MEMORY
  JSR ss_walk_frames_by_type
  PLA
  TAX
  RTS

; Per-frame callback for check_macro_recursion. TABP16 = current frame
; address. The frame's last 2 bytes are MACRO_ENTRY16 (saved by
; expand_macro into the activation payload at offset payload+3..4 = the
; very end of the frame).
recursion_check_callback:
  LDY #0
  LDA (TABP16),Y          ; frame_size
  SEC
  SBC #2                  ; offset of saved MACRO_ENTRY16 lo
  TAY
  LDA (TABP16),Y
  CMP MACRO_ENTRY16
  BNE .rcc_no_match
  INY
  LDA (TABP16),Y
  CMP MACRO_ENTRY16 + 1
  BNE .rcc_no_match
  JMP err_recursive_macro
.rcc_no_match:
  RTS


; Look up TOKEN's identifier in the parameter slots of the memory frame
; at TABP16 (typically the innermost macro frame, supplied by
; resolve_identifier from MACRO_LOOKUP_FRAME16). Walks the macro
; definition's parameter name list to find an index, then reads the
; matching slot from the frame.
;
; Frame payload (last bytes, low to high offset):
;   slots[0..N-1]   3 bytes each: fwdref, value_L, value_H
;   arg_count (= N) at offset frame_size - 8
;   scope_block      LABEL_SCOPE16 lo/hi, CACHED_HASH,
;                    prev_macro_lookup lo/hi, MACRO_ENTRY16 lo/hi at
;                    offsets frame_size - 7..-1
;
; On entry: TABP16 = memory frame address; TOKEN holds the identifier.
; On exit:  C=0 if found -- HEX16 (= OPERAND16) and IS_FWDREF set,
;             matching find_in_hash's contract.
;           C=1 if no parameter matched. HEX16/IS_FWDREF unchanged.
;           A, Y, HTTP16, TEMP clobbered. X preserved (the output file
;             handle in macro bodies, the activation byte index in
;             expand_macro Phase 1's nested-arg-parse path).
ss_lookup_param_slot:
  ; Save X -- callers depend on X surviving identifier lookup.
  TXA
  PHA
  ; Read frame_size and stash on the 6502 stack (used twice below).
  LDY #0
  LDA (TABP16),Y
  PHA
  ; Read arg_count = N at offset frame_size - 8.
  SEC
  SBC #8
  TAY
  LDA (TABP16),Y                 ; A = N
  TAX                             ; X = remaining param iterations
  ; Compute start_of_slots offset = (frame_size - 8) - 3*N. Result
  ; lives in TEMP (advanced 3 bytes per slot during the walk below).
  STA TEMP                       ; TEMP = N
  ASL                             ; 2N
  CLC
  ADC TEMP                       ; 3N
  STA TEMP                       ; TEMP = 3N
  TYA                            ; A = arg_count_offset
  SEC
  SBC TEMP                       ; A = start_of_slots offset
  STA TEMP                       ; TEMP = current slot offset
  ; Read MACRO_ENTRY16 from the scope_block (last 2 bytes of frame).
  PLA                            ; A = frame_size
  SEC
  SBC #2                         ; offset of MACRO_ENTRY16 lo
  TAY
  LDA (TABP16),Y
  STA HTTP16
  INY
  LDA (TABP16),Y
  STA HTTP16 + 1
  ; The macro def now starts with a 1-byte parameter count followed by
  ; the param-name list. MACRO_ENTRY16 still points at the count byte;
  ; advance HTTP16 past it so the walk below sees param1 at offset 0.
  CLC
  LDA HTTP16
  ADC #$01
  STA HTTP16
  LDA HTTP16 + 1
  ADC #$00
  STA HTTP16 + 1
  ; Walk the param-name list. X is the number of names still to check;
  ; on each miss, advance HTTP16 past the null terminator, bump TEMP by
  ; 3 (next slot), and DEX. Termination is count-driven now that the
  ; trailing empty-string sentinel is gone.
.lps_iter:
  CPX #0
  BEQ .lps_not_found             ; walked all N names without a match
  LDY #0
.lps_cmp:
  LDA (HTTP16),Y
  CMP TOKEN,Y
  BNE .lps_skip
  CMP #0
  BEQ .lps_match
  INY
  BNE .lps_cmp                    ; tokens are < 256 chars
.lps_skip:
  ; Names differ. Advance past this param's null and try the next one.
  ; Y indexes into the param name; walk to its null.
.lps_to_null:
  LDA (HTTP16),Y
  BEQ .lps_past_null
  INY
  BNE .lps_to_null
.lps_past_null:
  TYA
  SEC                             ; +1 to skip the null
  ADCA16 HTTP16, HTTP16
  ; slot offset += 3
  LDA TEMP
  CLC
  ADC #3
  STA TEMP
  DEX
  JMP .lps_iter
.lps_match:
  ; Slot at offset TEMP holds [fwdref, value_L, value_H].
  LDY TEMP
  LDA (TABP16),Y
  STA IS_FWDREF
  INY
  LDA (TABP16),Y
  STA HEX16
  INY
  LDA (TABP16),Y
  STA HEX16 + 1
  ; Restore X and return C=0 (found).
  PLA
  TAX
  CLC
  RTS
.lps_not_found:
  PLA
  TAX
  SEC
  RTS


; Expand a macro invocation
; On entry: MACRO_DEF_PTR points to the macro entry
;           ([N], param1\0, ..., paramN\0, body\0)
;           TOKEN contains the macro name
; On exit: Memory source pushed
expand_macro:
.ARG_SIZE = 3 ; Size of each macro argument (value_L, value_H, is_fwdref)
                ; Max arguments = 256 / .ARG_SIZE = 85
  ; Save original macro entry address before MACRO_DEF_PTR is modified
  CP16 MACRO_DEF_PTR16, MACRO_ENTRY16
  ; Check for recursive macro invocation
  JSR check_macro_recursion
  ; Save X (output file handle) - we'll use X as index into MACRO_ACTIVATION
  TXA
  PHA
  ; DON'T push label scope yet - we need parent's scope to look up arguments
  ; Parse arguments first, storing values in fixed buffer

  ; ----- Phase 1: Capture argument values -----
  ; Read N (the count byte) from the def, stash it in MACRO_ARG_REMAIN,
  ; and advance MACRO_DEF_PTR16 past the count byte so the param-name
  ; walk below sees param1 at offset 0. After Phase 1, MACRO_DEF_PTR16
  ; lands directly on the body's first byte (no terminator to skip).
  LDY #$00
  LDA (MACRO_DEF_PTR16),Y
  STA MACRO_ARG_REMAIN
  CLC
  LDA MACRO_DEF_PTR16
  ADC #$01
  STA MACRO_DEF_PTR16
  LDA MACRO_DEF_PTR16 + 1
  ADC #$00
  STA MACRO_DEF_PTR16 + 1
  ; X = index into MACRO_ACTIVATION for storing values
  ; Each entry: [is_fwdref][value_L][value_H] = 3 bytes
  LDX #$00
.parse_loop:
  ; Out of remaining params? Done with arg parsing.
  LDA MACRO_ARG_REMAIN
  BEQ .parse_done
  ; Skip past parameter name
  LDY #$FF
.skip_param:
  INY
  LDA (MACRO_DEF_PTR16),Y
  BNE .skip_param
  ; Advance MACRO_DEF_PTR past the null terminator
  TYA
  SEC                   ; +1 for null
  ADCA16 MACRO_DEF_PTR16, MACRO_DEF_PTR16
  ; Check for argument in input
  JSR check_for_end_of_line
  BCC .have_arg
  JMP err_too_few_arguments
.have_arg:
  ; Parse argument expression (using PARENT's scope for lookups)
  JSR parse_expression
  ; MACRO_ACTIVATION bounds check.
  ; Buffer holds [slots..., arg_count, scope_block, prev_macro_lookup,
  ; macro_entry]; payload tail = 1 + 2 + 1 + 2 + 2 = 8 bytes (was 6
  ; before MACRO_LOOKUP_FRAME16 was threaded through frames). Payload
  ; size must be <= 32 (= MACRO_ACTIVATION_LIMIT - MACRO_ACTIVATION).
  ; After this iteration the next 3-byte slot needs to fit too, so we
  ; require byte_count + 3 + 8 <= 32. CPX limit = 32 - 3 - 8 + 1 = 22,
  ; which caps args at 24/3 = 8 (MACRO_MAX_ARGS). The frame_size guard
  ; in .args_done_ok also enforces the 1-byte frame_size limit, but for
  ; typical short macro names that limit is much looser than this
  ; buffer cap.
  CPX #MACRO_ACTIVATION_LIMIT - MACRO_ACTIVATION - .ARG_SIZE - 8 + $01
  BCC .arg_ok         ; X < limit: safe
.arg_overflow:
  JMP err_too_many_arguments
.arg_ok:
  ; Store fwdref flag and value in fixed buffer
  LDA IS_FWDREF
  STA MACRO_ACTIVATION,X
  INX
  LDA OPERAND16
  STA MACRO_ACTIVATION,X
  INX
  LDA OPERAND16 + 1
  STA MACRO_ACTIVATION,X
  INX
  ; Decrement remaining-arg count; if 0, we just consumed the last param.
  DEC MACRO_ARG_REMAIN
  BEQ .parse_done
  ; More params expected - require comma
  JSR check_for_end_of_line
  BCS .too_few_next    ; EOL but more params expected
  CMP #','
  BNE .arg_err_comma
  JSR read_char
  JMP .parse_loop
.too_few_next:
  JMP err_too_few_arguments
.arg_err_comma:
  JMP err_comma_expected
.parse_done:
  ; Check for extra arguments (should be at end of line now)
  JSR check_for_end_of_line
  BCS .args_done_ok
  JMP .too_many
.args_done_ok:
  ; ----- Build the activation payload, then push the macro's memory
  ;       frame in a single step -----
  ;
  ; Payload layout (low offset to high) staged in MACRO_ACTIVATION:
  ;   bytes 0..byte_count-1 : slots, copied verbatim from MACRO_ACTIVATION
  ;                           (3 bytes per slot: fwdref, value_L, value_H)
  ;   byte byte_count       : arg_count (= byte_count / 3)
  ;   bytes +1..+5          : scope_block to restore on pop --
  ;                             LABEL_SCOPE16 lo/hi, CACHED_HASH,
  ;                             MACRO_ENTRY16 lo/hi
  ;
  ; The scope_block stays at the end of the payload so the existing
  ; consumers (pop_label_scope_from_frame at frame_size-5..-1, and
  ; check_macro_recursion's callback at frame_size-2..-1) keep working
  ; without changes. Phase 4.6 will start reading arg_count + slots
  ; here; for now they're written in parallel with the legacy hash
  ; path so the migration is observable and reversible.
  ;
  ; X is the arg byte count from Phase 1. The args are already in
  ; MACRO_ACTIVATION at offsets 0..X-1 (and MACRO_ACTIVATION aliases the
  ; same buffer), so we just append arg_count + scope_block in place.
  STX TEMP                  ; TEMP = byte_count
  ; The frame_size byte at offset 0 is one byte, so the total frame
  ; size must be <= 255. Frame layout for a memory frame on top of
  ; another memory frame is the worst case:
  ;   1 (frame_size) + name_len + 1 (null) + 1 (curr_type)
  ;   + 1 (prev_type) + 2 (line) + 2 (prev_data) + byte_count
  ;   + 8 (arg_count + scope_block + prev_macro_lookup + macro_entry)
  ; = 16 + name_len + byte_count
  ; Bail with err_too_many_arguments if this would overflow the byte.
  ; Using the worst case (memory parent) keeps the limit independent
  ; of who's calling us.
  LDY #$FF
.measure_name:
  INY
  LDA SS_NAME,Y
  BNE .measure_name
  ; Y = name_len
  TYA
  CLC
  ADC TEMP                  ; A = name_len + byte_count
  BCC .frame_size_check_2   ; no overflow yet
  JMP .too_many
.frame_size_check_2:
  CLC
  ADC #16                   ; A = name_len + byte_count + 16
  BCC .frame_size_ok        ; fits in a byte
  JMP .too_many             ; would overflow frame_size byte
.frame_size_ok:
  ; Compute arg_count = byte_count / 3 by repeated subtraction;
  ; X runs down to 0, A accumulates the count.
  LDA #0
.div_3:
  CPX #0
  BEQ .div_done
  DEX
  DEX
  DEX
  CLC
  ADC #1
  JMP .div_3
.div_done:
  ; A = arg_count. Write it at offset byte_count (right after slots).
  LDY TEMP
  STA MACRO_ACTIVATION,Y
  INY
  ; Append the 7-byte scope_block (current/parent scope state). The
  ; prev_macro_lookup snapshot sits between CACHED_HASH and MACRO_ENTRY16
  ; so MACRO_ENTRY16 stays at frame_size - 2..-1 (recursion check
  ; offset unchanged) and pop_label_scope_from_frame can read the
  ; restorable fields contiguously starting at frame_size - 7.
  LDA LABEL_SCOPE16
  STA MACRO_ACTIVATION,Y
  INY
  LDA LABEL_SCOPE16 + 1
  STA MACRO_ACTIVATION,Y
  INY
  LDA CACHED_HASH
  STA MACRO_ACTIVATION,Y
  INY
  LDA MACRO_LOOKUP_FRAME16
  STA MACRO_ACTIVATION,Y
  INY
  LDA MACRO_LOOKUP_FRAME16 + 1
  STA MACRO_ACTIVATION,Y
  INY
  LDA MACRO_ENTRY16
  STA MACRO_ACTIVATION,Y
  INY
  LDA MACRO_ENTRY16 + 1
  STA MACRO_ACTIVATION,Y
  INY
  ; Y = total payload size = byte_count + 8.
  STY TEMP
  ; Set up the new scope: EXPANSION_ID is monotonic, LABEL_SCOPE16 =
  ; expansion id, CACHED_HASH derived from the low byte through
  ; scramble_table. Pre-Phase-3.6 this lived in push_label_scope.
  INC16 EXPANSION_ID16
  CP16 EXPANSION_ID16, LABEL_SCOPE16
  LDA EXPANSION_ID16
  AND #$7F
  TAY
  LDA scramble_table,Y
  STA CACHED_HASH
  INC SCOPE_DEPTH
  ; Push the memory frame carrying the activation payload. TOKEN still
  ; holds the macro name (the param-copy loop below will clobber it,
  ; but the push captures the name into the frame first). Tracebacks
  ; therefore name the macro correctly.
  SET16 MACRO_ACTIVATION, SS_PAYLOAD16
  LDA TEMP                  ; payload size (byte_count + 8)
  JSR push_memory_source_with_payload
  ; Anchor MACRO_LOOKUP_FRAME16 at the new top frame so subsequent
  ; resolve_identifier calls (during the macro body) find this frame's
  ; parameter slots in O(1). The previous value was already stashed
  ; into the frame's payload above; pop_label_scope_from_frame
  ; restores it on pop.
  LDA SS_P16
  STA MACRO_LOOKUP_FRAME16
  LDA SS_P16 + 1
  STA MACRO_LOOKUP_FRAME16 + 1

  ; Phase 1 already advanced MACRO_DEF_PTR16 past every param name (and
  ; past the count byte at entry), so it now sits exactly at the body's
  ; first byte. Install it as the new memory source pointer.
  CP16 MACRO_DEF_PTR16, SS_MEM_PTR16
  ; Restore X (output file handle)
  PLA
  TAX
  RTS
.too_many:
  JMP err_too_many_arguments
