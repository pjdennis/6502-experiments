; macro_expansion.asm - Macro invocation and expansion
;
; Provides: check_macro_recursion, expand_macro
;
; Requires:
;   CURR_CHAR (asm.asm alias; backing storage in file_stack.asm)
;   TOKEN, PASS (asm.asm)
;   IN_MACRO_DEF (macro_capture.asm)
;   MACRO_ARG_BUF, MACRO_ARG_LIMIT, MACRO_ENTRY16, OPERAND16 (asm.asm)
;   LABEL_TYPE, LABEL_TYPE_MACRO (common.asm)
;   read_char (asm.asm alias; implemented in file_stack.asm)
;   check_for_end_of_line (tokenizer.asm)
;   parse_expression (expressions.asm)
;   select_label_hash_table (common.asm)
;   hash_add (hash_table.asm), store_hash_value (common.asm)
;   push_label_scope (label_scope.asm), push_memory_source (file_stack.asm)
;   err_* (errors.asm)

  .code


; Check if macro is already being expanded (recursion check)
; Walks the scope stack comparing 2-byte macro entry addresses
; On entry: MACRO_ENTRY16 contains the macro's hash table entry address
; On exit: Returns normally if no recursion, jumps to err_recursive_macro if found
;          Uses TABP16 as walk pointer, A/Y clobbered, X preserved
check_macro_recursion:
  ; Walk scope stack from bottom to current position
  SET16 SCOPE_STACK, TABP16
.loop:
  ; Check if we've reached current scope pointer
  CMP16 TABP16, SCOPE_PTR16
  BEQ .done                 ; Reached current position, no recursion
  ; Compare macro address at offset +3 with MACRO_ENTRY16
  LDY #3
  LDA (TABP16),Y
  CMP MACRO_ENTRY16
  BNE .next
  INY
  LDA (TABP16),Y
  CMP MACRO_ENTRY16 + 1
  BNE .next
  ; Match found - recursion detected
  JMP err_recursive_macro
.next:
  ; Advance to next entry (+5 bytes)
  CLC
  ADCI16 TABP16, 5, TABP16
  JMP .loop
.done:
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
  ; MACRO_ARG_BUF bounds check
  ; Check if X < MACRO_ARG_LIMIT - MACRO_ARG_BUF - .ARG_SIZE + $01 (room for one more entry)
  CPX #MACRO_ARG_LIMIT - MACRO_ARG_BUF - .ARG_SIZE + $01
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
  BCC .too_many
  ; NOW push label scope for the child macro
  JSR push_label_scope

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
  ; Push memory source and set up pointers
  JSR push_memory_source
  ; Set memory pointer to body_ptr from macro definition
  ; Add one to MACR_DEF_PTR16 to skip 0 terminator and save to memory source
  CLC
  ADCI16 MACRO_DEF_PTR16, $01, SS_MEM_PTR16
  ; Restore X (output file handle)
  PLA
  TAX
  RTS
.too_many:
  JMP err_too_many_arguments
