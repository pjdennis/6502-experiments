; macro_expansion.asm - Macro invocation and expansion
;
; Provides: check_macro_recursion, expand_macro
;
; Requires:
;   CURR_CHAR (asm.asm alias; backing storage in source_stack.asm)
;   TOKEN, PASS, MACRO_ACTIVATION (asm.asm)
;   IN_MACRO_DEF (macro_capture.asm)
;   MACRO_ARG_BUF, MACRO_ARG_LIMIT, MACRO_ENTRY16, OPERAND16 (asm.asm)
;   LABEL_TYPE, LABEL_TYPE_MACRO (common.asm)
;   LABEL_SCOPE16, CACHED_HASH, scramble_table (hash_table.asm)
;   EXPANSION_ID16, SCOPE_DEPTH (label_scope.asm)
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


; Expand a macro invocation
; On entry: MACRO_DEF_PTR points to the  macro entry
;           (param1\0, param2\0, ..., \0, body\0)
;           TOKEN contains the macro name
; On exit: Memory source pushed
expand_macro:
.ARG_SIZE = 3 ; Size of each macro argument (value_L, value_H, is_fwdref)
                ; Max arguments = 256 / .ARG_SIZE = 85
  ; Save original macro entry address before MACRO_DEF_PTR is modified
  CP16 MACRO_DEF_PTR16, MACRO_ENTRY16
  ; Check for recursive macro invocation
  JSR check_macro_recursion
  ; Save X (output file handle) - we'll use X as index into MACRO_ARG_BUF
  TXA
  PHA
  ; DON'T push label scope yet - we need parent's scope to look up arguments
  ; Parse arguments first, storing values in fixed buffer

  ; ----- Phase 1: Capture argument values -----
  ; X = index into MACRO_ARG_BUF for storing values
  ; Each entry: [is_fwdref][value_L][value_H] = 3 bytes
  LDX #$00
.parse_loop:
  ; Check if we're at end of parameter list (empty string)
  LDY #$00
  LDA (MACRO_DEF_PTR16),Y
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
  ; MACRO_ARG_BUF bounds check.
  ; The buffer doubles as the activation-payload staging area: after
  ; Phase 1 finishes we append a 6-byte tail (1 arg_count + 5
  ; scope_block) starting at offset byte_count, so the limit needs to
  ; reserve room for that as well as the next 3-byte slot we're about
  ; to write. Limit is 256 - 3 - 6 + 1 = 248 (max 83 args; with 84+
  ; the tail would spill out of MACRO_ARG_BUF / MACRO_ACTIVATION).
  CPX #MACRO_ARG_LIMIT - MACRO_ARG_BUF - .ARG_SIZE - 6 + $01
  BCC .arg_ok         ; X < limit: safe
.arg_overflow:
  JMP err_too_many_arguments
.arg_ok:
  ; Store fwdref flag and value in fixed buffer
  LDA IS_FWDREF
  STA MACRO_ARG_BUF,X
  INX
  LDA OPERAND16
  STA MACRO_ARG_BUF,X
  INX
  LDA OPERAND16 + 1
  STA MACRO_ARG_BUF,X
  INX
  ; Check if more params expected
  LDY #$00
  LDA (MACRO_DEF_PTR16),Y
  BEQ .parse_done      ; Last param, skip comma check
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
  ;   bytes 0..byte_count-1 : slots, copied verbatim from MACRO_ARG_BUF
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
  ; MACRO_ARG_BUF at offsets 0..X-1 (and MACRO_ACTIVATION aliases the
  ; same buffer), so we just append arg_count + scope_block in place.
  STX TEMP                  ; TEMP = byte_count
  ; The frame_size byte at offset 0 is one byte, so the total frame
  ; size must be <= 255. Frame layout for a memory frame on top of
  ; another memory frame is the worst case:
  ;   1 (frame_size) + name_len + 1 (null) + 1 (curr_type)
  ;   + 1 (prev_type) + 2 (line) + 2 (prev_data) + byte_count
  ;   + 6 (arg_count + scope_block payload tail)
  ; = 14 + name_len + byte_count
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
  ADC #14                   ; A = name_len + byte_count + 14
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
  ; Append the 5-byte scope_block (current/parent scope state).
  LDA LABEL_SCOPE16
  STA MACRO_ACTIVATION,Y
  INY
  LDA LABEL_SCOPE16 + 1
  STA MACRO_ACTIVATION,Y
  INY
  LDA CACHED_HASH
  STA MACRO_ACTIVATION,Y
  INY
  LDA MACRO_ENTRY16
  STA MACRO_ACTIVATION,Y
  INY
  LDA MACRO_ENTRY16 + 1
  STA MACRO_ACTIVATION,Y
  INY
  ; Y = total payload size = byte_count + 6.
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
  LDA TEMP                  ; payload size (byte_count + 6)
  JSR push_memory_source_with_payload

  ; ----- Phase 2: Populate child macro scope with parameter values -----
  ; Restore params start to MACRO_DEF_PTR
  CP16 MACRO_ENTRY16, MACRO_DEF_PTR16
  ; Reset X to read values from start of macro arg buffer
  LDX #$00
  ; Now iterate through params and add to hash with stored values
.add_loop:
  ; Check if at end of parameter list
  LDY #$00
  LDA (MACRO_DEF_PTR16),Y
  BEQ .add_done
  ; Copy param name to TOKEN
  LDY #$FF
.copy_param:
  INY
  LDA (MACRO_DEF_PTR16),Y
  STA TOKEN,Y
  BNE .copy_param
  ; Advance MACRO_DEF_PTR past param name
  TYA
  SEC ; +1 for null terminator
  ADCA16 MACRO_DEF_PTR16, MACRO_DEF_PTR16 ; MACRO_DEF_PTR + A + 1 -> MACRO_DEF_PTR
  ; Load fwdref and value from buffer
  LDA MACRO_ARG_BUF,X
  STA IS_FWDREF
  INX
  LDA MACRO_ARG_BUF,X
  STA OPERAND16
  INX
  LDA MACRO_ARG_BUF,X
  STA OPERAND16 + 1
  INX
  ; Skip adding if forward ref in pass 1
  LDA IS_FWDREF
  BEQ .do_add
  BIT PASS
  BPL .add_loop         ; Pass 1 fwdref: skip
  ; Pass 2: always add
.do_add:
  ; Add parameter to macro-local scope
  LDA #LABEL_TYPE_MACRO
  STA LABEL_TYPE
  JSR select_label_hash_table
  JSR hash_add
  BCS .add_loop         ; Already exists (pass 1), skip store
  ; Store value (OPERAND16 aliased to HEX16)
  JSR store_hash_value
  JMP .add_loop
.add_done:
  ; Memory source was already pushed above (right after the activation
  ; payload was built). Install the new body pointer now that param
  ; parsing is finished. MACRO_DEF_PTR16 currently points at the null
  ; separator between the param list and the body; +1 lands on the
  ; body's first byte.
  CLC
  ADCI16 MACRO_DEF_PTR16, $01, SS_MEM_PTR16
  ; Restore X (output file handle)
  PLA
  TAX
  RTS
.too_many:
  JMP err_too_many_arguments
