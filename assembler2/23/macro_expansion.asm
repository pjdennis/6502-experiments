; macro_expansion.asm - Macro definition, expansion, and body capture
;
; Provides: dir_macro, check_macro_recursion, expand_macro,
;           capture_macro_line, find_directive_handler
;
; Requires:
;   CURR_CHAR (asm.asm alias; backing storage in file_stack.asm)
;   TOKEN, PASS (asm.asm)
;   IN_MACRO_DEF (macro_expansion.asm)
;   MACRO_ARG_BUF, MACRO_ARG_LIMIT, MACRO_ENTRY16, OPERAND16 (asm.asm)
;   LABEL_TYPE, LABEL_TYPE_MACRO (common.asm)
;   read_char (asm.asm alias; implemented in file_stack.asm)
;   read_token, compare_end_of_token, check_for_end_of_line (tokenizer.asm)
;   parse_expression (expressions.asm), advance_heap (common.asm)
;   select_instruction_hash_table (common.asm)
;   select_label_hash_table (common.asm)
;   find_in_hash_instruction, add_macro_to_hash, hash_add (hash_table.asm), store_hash_value (common.asm)
;   push_label_scope (label_scope.asm), push_memory_source (file_stack.asm)
;   err_* (errors.asm)

  .zeropage

IN_MACRO_DEF:    .byte        ; Flag: currently capturing macro body ($FF = capturing)

  .code


; Process .macro directive
; Syntax: .macro NAME [param1 param2 ...]
; Creates entry in LHASHTAB: [escape header][name $00][params...][$00][body $00]
dir_macro:
  ; Skip spaces and read macro name
  JSR check_for_end_of_line
  BCC .has_name
  JMP err_macro_name_expected
.has_name:
  JSR read_token       ; Macro name now in TOKEN, current char in CURR_CHAR
  ; Check for instruction collision in IHASHTAB
  JSR select_instruction_hash_table
  JSR find_in_hash_instruction
  BCS .no_instruction_collision
  ; Found in IHASHTAB - check if it's a directive (directives can be shadowed)
  LDA (TABP16),Y
  CMP #MODE_DIRECTIVE
  BEQ .no_instruction_collision
  JMP err_macro_shadows_instruction
.no_instruction_collision:
  ; Save LABEL_SCOPE16 before add_macro_to_hash clobbers it
  PUSH16 LABEL_SCOPE16
  ; Add macro to LHASHTAB
  JSR select_label_hash_table
  JSR add_macro_to_hash
  ; Restore LABEL_SCOPE16
  POP16 LABEL_SCOPE16
  BCC .name_ok         ; C=0 means new entry added
  ; Name already exists - pass 2 expects this, pass 1 is duplicate error
  BIT PASS
  BMI .pass2_skip_add
  JMP err_duplicate_macro
.pass2_skip_add:
  ; Pass 2: skip adding, just set flag to enable body skipping
  ; (body was already captured in pass 1)
  LDA #$FF
  STA IN_MACRO_DEF
  JMP skip_rest_of_line
.name_ok:
  ; Add macro entry value
  ; MEMP16 points to location at which to store the value (directly after key)
  ; TABP16 points to the macro name on heap
  .ifdef enable_debug
  ; Supports the 'show_macros' debug option
  CP16 TABP16, MACRO_PTR16
  .endif
.param_loop:
  JSR check_for_end_of_line
  BCS .params_done     ; End of line, no more params
  ; Read parameter name
  JSR read_token       ; Param name in TOKEN, current char in CURR_CHAR
  ; Store parameter name on heap (null-terminated)
  LDY #$FF
.copy_param:
  INY
  LDA TOKEN,Y
  STA (MEMP16),Y
  BNE .copy_param
  INY
  JSR advance_heap
  JSR check_for_end_of_line
  BCS .params_done
  CMP #','
  BNE .param_err_comma
  JSR read_char
  JMP .param_loop
.param_err_comma:
  JMP err_comma_expected
.params_done:
  ; Write empty string terminator for parameter list
  LDY #$00
  APPEND_HEAPI $00
  JSR advance_heap
  ; Update MACRO_DEF_PTR to point where body will be stored
  CP16 MEMP16, MACRO_DEF_PTR16
  ; Set IN_MACRO_DEF flag to start capturing
  LDA #$FF
  STA IN_MACRO_DEF
  ; Skip rest of line (already done by check_for_end_of_line)
  RTS


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
  ADCI16 MACRO_DEF_PTR16, $01, FS_MEM_PTR16
  ; Restore X (output file handle)
  PLA
  TAX
  RTS
.too_many:
  JMP err_too_many_arguments


; Look up TOKEN in IHASHTAB and extract directive handler address
; On entry: TOKEN contains the directive name
; On exit: C=0 if found, JUMP_TARGET16 contains handler address
;          C=1 if not found (not in IHASHTAB or not a directive)
;          A, Y are not preserved, X is preserved
find_directive_handler:
  JSR select_instruction_hash_table
  JSR find_in_hash_instruction
  BCS .not_found
  LDA (TABP16),Y
  CMP #MODE_DIRECTIVE
  BNE .not_found_set_carry
  INY
  LDA (TABP16),Y
  STA JUMP_TARGET16
  INY
  LDA (TABP16),Y
  STA JUMP_TARGET16 + 1
  CLC
  RTS
.not_found_set_carry:
  SEC
.not_found:
  RTS


; Capture a line during macro definition
; On entry: CURR_CHAR contains first character of line
; On exit: Line copied to heap (with '\n'), or .endmacro processed
;
; Strategy: Copy whole line to heap, then check if it was .endmacro.
; If so, undo the copy and process .endmacro normally.
; In pass 2, skip heap copy - just scan for .endmacro detection.
capture_macro_line:
  TXA                    ; Save output file handle
  PHA
  BIT PASS
  BPL .pass1
  JMP .pass2
.pass1:
  ; === Pass 1: Copy to heap with compression ===
  ; Comments stripped, consecutive spaces collapsed (except in strings)
  CP16 MEMP16, MACRO_DEF_PTR16 ; Save heap pos for potential undo
  LDX #$00               ; Space indicator - $01 if last char was a space, $00 otherwise
  LDY #0                 ; Capture index
  LDA CURR_CHAR
  BNE .process           ; Always taken
.next:
  JSR read_char
  BCS .eof_error
.process:
  CMP #'\n'
  BNE .not_newline
  JMP .newline
.not_newline:
  CMP #';'
  BNE .not_semi
.skip_comment:
  JSR read_char
  BCS .eof_error
  CMP #'\n'
  BNE .skip_comment
  JMP .newline
.not_semi:
  CMP #'"'
  BEQ .string_lit
  CMP #'\''
  BEQ .char_lit
  CMP #' '
  BEQ .space
  ; Regular character
  LDX #$00               ; Clear last space indicator
.capture:
  APPEND_HEAPA_ADVANCE
  JMP .next
.eof_error:
  JMP err_unclosed_macro
.space:
  ; Space, so check for consecutives
  CPX #$01                 ; Check if last character was a space
  BEQ .next                ; Last char was a space so skip this one
  INX                      ; Set indicator that last character was a space
  BNE .capture             ; Always taken
.string_lit:
  ; Output string definition from opening " through closing "
  LDX #$00                 ; Clear last_space
  APPEND_HEAPA             ; Capture the opening quote
.string_lit_loop:
  JSR read_char            ; Read the current char and capture it
  BCS .eof_error
  APPEND_HEAPA
  ; Conditionally advance heap while preserving current character
  BPL .string_lit_no_advance
  JSR advance_heap
  LDA CURR_CHAR
.string_lit_no_advance:
  CMP #'\\'                ; Was it the escape character?
  BNE .string_lit_not_escape
  ; Escape character so read and capture the next char too
  JSR read_char
  BCS .eof_error
  APPEND_HEAPA
  BNE .string_lit_loop     ; Always taken
.string_lit_not_escape:
  CMP #'"'                 ; Was it the terminating string character?
  BNE .string_lit_loop     ; No so process the next character
  ; Terminator character so we are done with the string
  JMP .next
.char_lit:
  ; Output char definition from opening ' through closing '
  LDX #$00                 ; Clear last_space
  APPEND_HEAPA             ; Capture the opening quote
  JSR read_char            ; Read the next char and write it
  BCS .eof_error
  APPEND_HEAPA
  CMP #'\\'                ; Was it the escape character?
  BNE .char_lit_not_escape
  ; Escape character so read and capture the next char too
  JSR read_char
  BCS .eof_error
  APPEND_HEAPA
.char_lit_not_escape:
  JSR read_char            ; Read the next character
  BCS .eof_error
  ; It should be a closing single quote
  CMP #'\''
  BEQ .capture
  JMP err_invalid_char_literal
.newline:
  APPEND_HEAPA             ; Capture the newline
  JSR advance_heap
  ; Now check if this line was .endmacro or .macro
  CP16 MACRO_DEF_PTR16, TABP16
  ; Skip leading spaces
  LDY #0
.skip_space:
  LDA (TABP16),Y
  CMP #' '
  BNE .check_dot
  INY
  BNE .skip_space
.check_dot:
  CMP #'.'
  BNE .keep_line
  CPY #$00
  BEQ .keep_line           ; Column 0 = local label, not directive
  ; It's a directive
  TYA
  SEC                      ; +1
  ADCA16 TABP16, TABP16 ; Advance TABP16 to point to the start of the directive
  ; Copy directive name from heap (TABP16) to TOKEN
  LDY #$00
.copy_dir:
  LDA (TABP16),Y
  JSR compare_end_of_token
  BCC .copy_dir_done          ; End of token character
  STA TOKEN,Y
  INY
  BNE .copy_dir
.copy_dir_done:
  LDA #$00
  STA TOKEN,Y                 ; Null-terminate
  ; Look up in IHASHTAB
  JSR find_directive_handler
  BCS .keep_line              ; Not found — not a known directive
  ; Check for .endmacro
  CMPI16 JUMP_TARGET16, dir_endmacro
  BEQ .found_endmacro
  ; Check for .macro (nested = error)
  CMPI16 JUMP_TARGET16, dir_macro
  BNE .keep_line              ; Other directive — keep as macro body
  JMP err_nested_macro_definition
.found_endmacro:
  ; Found .endmacro. Restore heap to undo the copy
  CP16 MACRO_DEF_PTR16, MEMP16
  ; At end of macro definition. Write $00 terminator to body
  LDY #0
  APPEND_HEAPI $00
  JSR advance_heap
  ; The debug version of the assembler supports displaying the captured macro
  .ifdef enable_debug
  LDA SHOW_MACROS
  BEQ .not_showing_macros
  JSR show_macros
.not_showing_macros:
  .endif
  ; Clear the capturing flag
  LDA #$00
  STA IN_MACRO_DEF
  JSR skip_rest_of_line
.keep_line:
  ; Restore X (output file handle)
  PLA
  TAX
  RTS

  ; === Pass 2: Skip without copying to heap ===
  ; Just detect .endmacro to clear IN_MACRO_DEF flag
.pass2:
  LDA CURR_CHAR
  CMP #' '
  BEQ .p2_scan_spaces
  ; First column - not a directive (even if '.')
  CMP #'\n'
  BEQ .keep_line           ; Empty line
  JMP .p2_skip             ; Column 0 content, skip line
.p2_scan_spaces:
  JSR read_char
  BCC .p2_scan_check
  JMP err_unclosed_macro   ; EOF in macro
.p2_scan_check:
  CMP #' '
  BEQ .p2_scan_spaces
  CMP #'\n'
  BEQ .keep_line           ; Blank line
  CMP #'.'
  BNE .p2_skip             ; Not a directive
  ; Check if directive is .endmacro
  JSR read_char            ; Read char after '.'
  JSR read_token           ; Read directive name into TOKEN
  JSR find_directive_handler
  BCS .p2_skip               ; Not found
  CMPI16 JUMP_TARGET16, dir_endmacro
  BEQ .p2_found_endmacro
  ; Not .endmacro — fall through to .p2_skip
.p2_skip:
  PLA                      ; Restore X (output file handle)
  TAX
  JMP skip_rest_of_line    ; Tail call
.p2_found_endmacro:
  LDA #$00                 ; Clear the capturing flag
  STA IN_MACRO_DEF
  PLA                      ; Restore X (output file handle)
  TAX
  JMP skip_rest_of_line    ; Tail call
