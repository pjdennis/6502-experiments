; directives.asm - Directive dispatch, data directives, conditional assembly
;
; Provides: swap_pc_with_save, process_directive, process_conditional_directive,
;           emit_quoted, set_data_mode, data_parameters_loop,
;           handle_reserve, process_ifdef, process_endif,
;           directive string constants (directive_include, etc.)
;
; Requires:
;   CURR_CHAR (asm.asm alias; backing storage in file_stack.asm)
;   TOKEN, PASS, PC16, PC_SAVE16, OPERAND16, IN_ZEROPAGE (asm.asm)
;   IFDEF_DECISIONS (asm.asm), COND_DEPTH, SKIP_DEPTH, IFDEF_INDEX (directives.asm)
;   read_char (asm.asm alias; implemented in file_stack.asm)
;   read_token, read_filename (tokenizer.asm)
;   compare_token (hash_table.asm)
;   skip_rest_of_line, check_for_end_of_line (tokenizer.asm)
;   select_label_hash_table (common.asm)
;   emit, advance_pc_to_hex16 (output.asm)
;   decode_escape (tokenizer.asm)
;   parse_value (expressions.asm)
;   process_macro (macro_expansion.asm)
;   push_file_stack (file_stack.asm)
;   err_* (errors.asm)

  .zeropage

DATA_MODE:       .byte        ; Data directive mode: 1=.byte 2=.word 3=.asciiz
COND_DEPTH:      .byte        ; Conditional assembly nesting depth
SKIP_DEPTH:      .byte        ; Depth where skipping started (0 = not skipping)
IFDEF_INDEX:     .byte        ; Current index into IFDEF_DECISIONS buffer

  .code

; Constants
DATA_MODE_BYTE   = 1          ; 1 Byte
DATA_MODE_WORD   = 2          ; 2 Bytes
DATA_MODE_ASCIIZ = 3          ; 1 Byte, null terminated


; Swap PC16 with PC_SAVE16
; Used by .zeropage/.code directive handlers
; On exit A, Y are not preserved
;         X is preserved
swap_pc_with_save:
  ; Swap PC16 low byte with save location
  LDA PC16
  LDY PC_SAVE16
  STY PC16
  STA PC_SAVE16
  ; Swap PC16 high byte with save location
  LDA PC16+$01
  LDY PC_SAVE16+$01
  STY PC16+$01
  STA PC_SAVE16+$01
  RTS


; On entry, A contains the first character of the directive
process_directive:
  JSR read_token       ; Current char in CURR_CHAR
  ; Reset LABEL_TYPE for directive string comparisons
  ; (compare_token checks LABEL_TYPE, must be GLOBAL for non-escape strings)
  LDA #LABEL_TYPE_GLOBAL
  STA LABEL_TYPE
  ; Check for 'include'
  SET16 directive_include, TABP16
  JSR compare_token
  BEQ .include
  ; Check for 'zeropage'
  SET16 directive_zeropage, TABP16
  JSR compare_token
  BEQ .zeropage
  ; Check for 'code'
  SET16 directive_code, TABP16
  JSR compare_token
  BEQ .code
  ; Check for 'byte'
  SET16 directive_byte, TABP16
  JSR compare_token
  BEQ .byte
  ; Check for 'word'
  SET16 directive_word, TABP16
  JSR compare_token
  BEQ .word
  ; Check for 'asciiz'
  SET16 directive_asciiz, TABP16
  JSR compare_token
  BEQ .asciiz
  ; Check for 'reserve'
  SET16 directive_reserve, TABP16
  JSR compare_token
  BEQ .reserve
  JSR process_conditional_directive ; Returns with C=0 if processed
  BCC .directive_done
  ; Check for 'macro'
  SET16 directive_macro, TABP16
  JSR compare_token
  BEQ .macro
  ; Check for 'endmacro'
  SET16 directive_endmacro, TABP16
  JSR compare_token
  BEQ .endmacro
  JMP err_unknown_directive
.directive_done:
  RTS
.include:
  JSR check_for_end_of_line
  BCC .get_name
  JMP err_filename_expected
.get_name:
  JSR read_filename
  JSR skip_rest_of_line
  JMP push_file_stack    ; Tail call
.zeropage:
  BIT IN_ZEROPAGE
  BMI .in_zeropage
  LDA #$FF
  STA IN_ZEROPAGE
  JSR swap_pc_with_save
.in_zeropage:
  JMP skip_rest_of_line  ; Tail call
.code:
  BIT IN_ZEROPAGE
  BPL .in_code
  LDA #$00
  STA IN_ZEROPAGE
  JSR swap_pc_with_save
.in_code:
  JMP skip_rest_of_line  ; Tail call
.byte:
  LDA #DATA_MODE_BYTE
  BIT IN_ZEROPAGE
  BMI .zp_alloc          ; In zeropage? check for operand-less form
  JMP set_data_mode
.word:
  LDA #DATA_MODE_WORD
  BIT IN_ZEROPAGE
  BMI .zp_alloc          ; In zeropage? check for operand-less form
  JMP set_data_mode
.asciiz:
  BIT IN_ZEROPAGE
  BMI .zp_asciiz_err
  LDA #DATA_MODE_ASCIIZ
  JMP set_data_mode
.zp_asciiz_err:
  JMP err_asciiz_in_zeropage
.reserve:
  JMP handle_reserve
.macro:
  JMP process_macro
.endmacro:
  JMP err_endmacro_without_macro

.zp_alloc:
  ; A = DATA_MODE (1=byte, 2=word)
  STA DATA_MODE
  JSR check_for_end_of_line
  BCC .zp_has_operand       ; Not EOL — has operand, use normal path
  ; Operand-less: emit A dummy bytes (1 for .byte, 2 for .word)
  LDA #$00
  JSR emit                  ; Advance ZP PC by 1
  LDA DATA_MODE
  CMP #DATA_MODE_WORD
  BNE .zp_done
  LDA #$00
  JSR emit                  ; Advance ZP PC by 2nd byte for .word
.zp_done:
  RTS
.zp_has_operand:
  JMP err_operand_in_zeropage


; On exit C=0 if processed; C=1 if not processed
;         A is not preserved
process_conditional_directive:
  ; Check for 'ifdef'
  SET16 directive_ifdef, TABP16
  JSR compare_token
  BEQ .ifdef
  ; Check for 'ifndef'
  SET16 directive_ifndef, TABP16
  JSR compare_token
  BEQ .ifndef
  ; Check for 'else'
  SET16 directive_else, TABP16
  JSR compare_token
  BEQ .else
  ; Check for 'endif'
  SET16 directive_endif, TABP16
  JSR compare_token
  BEQ .endif
  SEC ; Not processed
  RTS
.ifdef:
  JSR process_ifdef
  CLC
  RTS
.ifndef:
  JSR process_ifndef
  CLC
  RTS
.else:
  JSR process_else
  CLC
  RTS
.endif:
  JSR process_endif
  CLC
  RTS


directive_include:
  .asciiz "include"

directive_zeropage:
  .asciiz "zeropage"

directive_code:
  .asciiz "code"

directive_byte:
  .asciiz "byte"

directive_word:
  .asciiz "word"

directive_asciiz:
  .asciiz "asciiz"

directive_reserve:
  .asciiz "reserve"

directive_ifdef:
  .asciiz "ifdef"

directive_endif:
  .asciiz "endif"

directive_ifndef:
  .asciiz "ifndef"

directive_else:
  .asciiz "else"

directive_macro:
  .asciiz "macro"

directive_endmacro:
  .asciiz "endmacro"


; Read and emit quoted ASCII
; On entry A contains the first character within quotes
; On exit A contains the current character after the closing quote
;         X, Y are preserved
; Raises 'Closing quote not found' error if closing quote not found on current line
emit_quoted:
.loop:
  CMP #'\n'
  BEQ .err_closing_quote
  CMP #'"'
  BEQ .done
  CMP #'\\'
  BNE .not_escaped
  JSR read_char
  CMP #'\n'
  BEQ .err_closing_quote
  JSR decode_escape
.not_escaped:
  JSR emit
  JSR read_char
  BCC .loop
.err_closing_quote:
  JMP err_closing_quote_not_found
.done:
  JMP read_char        ; Tail call; read char after closing quote


; Handle .reserve N directive
; Reserves N bytes: zero-fill in .code, PC advance in .zeropage
handle_reserve:
  JSR skip_spaces
  JSR parse_value
  ; HEX16 (= OPERAND16) now holds the count
  ; Compute target: HEX16 = PC16 + count
  CLC
  LDA HEX16
  ADC PC16
  STA HEX16
  LDA HEX16+$01
  ADC PC16+$01
  STA HEX16+$01
  JSR advance_pc_to_hex16
  JMP skip_rest_of_line


set_data_mode:
  STA DATA_MODE
data_parameters_loop:
  JSR check_for_end_of_line
  BCS .data_done
  CMP #'"'            ; Quoted string
  BNE .data_value
  JSR read_char
  JSR emit_quoted
  JMP .data_check_more
.data_value:
  JSR parse_value
  LDA DATA_MODE
  CMP #DATA_MODE_WORD
  BEQ .data_emit_two_bytes  ; Mode 2 (.word): force 2 bytes
  ; Mode 1 (.byte) or Mode 3 (.asciiz): validate + emit 1 byte
  BIT PASS
  BPL .data_emit_one_byte   ; Skip validation on pass 1
  LDA OPERAND16+$01
  BEQ .data_emit_one_byte   ; Not an error
  JMP err_value_out_of_range
.data_emit_one_byte:
  LDA OPERAND16
  JSR emit
  JMP .data_check_more
.data_emit_two_bytes:
  LDA OPERAND16          ; Emit low byte
  JSR emit
  LDA OPERAND16+$01      ; Emit high byte
  JSR emit
.data_check_more:
  JSR check_for_end_of_line
  BCS .data_done
  CMP #','
  BNE .data_err_comma
  JSR read_char
  JMP data_parameters_loop
.data_err_comma:
  JMP err_comma_expected
.data_done:
  LDA DATA_MODE
  CMP #DATA_MODE_ASCIIZ
  BNE .data_rts
  LDA #$00
  JMP emit           ; Tail call: emit null terminator
.data_rts:
  RTS


; Process .ifdef directive
; Records decision in pass 1, replays in pass 2 for consistency with forward refs
process_ifdef:
  INC COND_DEPTH
  LDA COND_DEPTH
  CMP #17                  ; Check for nesting limit (16 levels max)
  BCS .nesting_too_deep
  LDA SKIP_DEPTH
  BNE .already_skipping    ; Already skipping, don't record or evaluate
  ; Evaluate condition
  JSR check_for_end_of_line
  BCC .has_label
  JMP err_label_expected
.has_label:
  JSR read_token           ; Expects current char in A
  ; Save X (global output file handle)
  TXA
  PHA
  ; Check for pass 2 - no need to look up label in pass 2
  BIT PASS
  BMI .pass2
  ; --- Pass 1: Evaluate and store decision ---
  LDX IFDEF_INDEX
  ; Increment and check for overflow (wrap from 255 to 0 = buffer full)
  INC IFDEF_INDEX
  BEQ .overflow            ; If wrapped to 0, we've used all 256 slots
  LDA #LABEL_TYPE_GLOBAL
  STA LABEL_TYPE
  JSR select_label_hash_table
  JSR find_in_hash         ; C=0 if found, C=1 if not found
  ; Save result: A = $FF if found (assemble), $00 if not found (skip)
  LDA #$00                 ; Default: not defined (skip)
  BCS .save_result         ; C=1 means not found
  LDA #$FF                 ; Found: defined (assemble)
.save_result:
  STA IFDEF_DECISIONS,X
  ; Branch based on decision value
  BEQ .start_skip          ; Not defined ($00) - start skipping
  BNE .done                ; Defined ($FF) - continue (no skip)
  ; --- Pass 2: Replay stored decision ---
.pass2:
  LDX IFDEF_INDEX
  INC IFDEF_INDEX
  LDA IFDEF_DECISIONS,X
  BEQ .start_skip
  BNE .done
.start_skip:
  LDA COND_DEPTH
  STA SKIP_DEPTH
.done:
  ; Restore X (global output file handle)
  PLA
  TAX
.already_skipping:
  JMP skip_rest_of_line
.overflow:
  JMP err_too_many_ifdefs
.nesting_too_deep:
  JMP err_conditional_nesting_too_deep


; Process .ifndef directive
; Records decision in pass 1, replays in pass 2 for consistency with forward refs
; Inverse of .ifdef: assembles if label NOT defined
process_ifndef:
  INC COND_DEPTH
  LDA COND_DEPTH
  CMP #17                  ; Check for nesting limit (16 levels max)
  BCS .nesting_too_deep
  LDA SKIP_DEPTH
  BNE .already_skipping    ; Already skipping, don't record or evaluate
  ; Evaluate condition
  JSR check_for_end_of_line
  BCC .has_label
  JMP err_label_expected
.has_label:
  JSR read_token           ; Expects current char in A
  ; Save X (global output file handle)
  TXA
  PHA
  ; Check for pass 2 - no need to look up label in pass 2
  BIT PASS
  BMI .pass2
  ; --- Pass 1: Evaluate and store decision ---
  LDX IFDEF_INDEX
  ; Increment and check for overflow (wrap from 255 to 0 = buffer full)
  INC IFDEF_INDEX
  BEQ .overflow            ; If wrapped to 0, we've used all 256 slots
  LDA #LABEL_TYPE_GLOBAL
  STA LABEL_TYPE
  JSR select_label_hash_table
  JSR find_in_hash         ; C=0 if found, C=1 if not found
  ; Save result (INVERTED): A = $FF if NOT found (assemble), $00 if found (skip)
  LDA #$FF                 ; Default: not defined (assemble for ifndef)
  BCS .save_result         ; C=1 means not found
  LDA #$00                 ; Found: defined (skip for ifndef)
.save_result:
  STA IFDEF_DECISIONS,X
  ; Branch based on decision value
  BEQ .start_skip          ; Defined ($00) - start skipping
  BNE .done                ; Not defined ($FF) - continue (no skip)
  ; --- Pass 2: Replay stored decision ---
.pass2:
  LDX IFDEF_INDEX
  INC IFDEF_INDEX
  LDA IFDEF_DECISIONS,X
  BEQ .start_skip
  BNE .done
.start_skip:
  LDA COND_DEPTH
  STA SKIP_DEPTH
.done:
  ; Restore X (global output file handle)
  PLA
  TAX
.already_skipping:
  JMP skip_rest_of_line
.overflow:
  JMP err_too_many_ifdefs
.nesting_too_deep:
  JMP err_conditional_nesting_too_deep


; Process .else directive
; Toggles skip state for current conditional block
process_else:
  ; 1. Validate we're in a conditional block
  LDA COND_DEPTH
  BEQ .error_else_without_ifdef
  ; 2. Check if this conditional already has .else
  TAY                          ; Y = COND_DEPTH (use Y, not X!)
  LDA ELSE_SEEN_ARRAY,Y
  BNE .error_duplicate_else
  ; 3. Mark .else seen at this depth
  LDA #$FF
  STA ELSE_SEEN_ARRAY,Y
  ; 4. Toggle skip state
  LDA SKIP_DEPTH
  BNE .currently_skipping
  ; Currently assembling - start skipping
  LDA COND_DEPTH
  STA SKIP_DEPTH
  JMP skip_rest_of_line
.currently_skipping:
  ; Check if skipping at THIS level
  CMP COND_DEPTH
  BNE .skip_at_outer_level     ; Skipping at outer level, stay skipped
  ; Skipping at this level - stop skipping
  LDA #$00
  STA SKIP_DEPTH
.skip_at_outer_level:
  JMP skip_rest_of_line
.error_else_without_ifdef:
  JMP err_else_without_ifdef
.error_duplicate_else:
  JMP err_duplicate_else


; Process .endif directive
process_endif:
  LDA COND_DEPTH
  BNE .has_ifdef       ; In a conditional block
  JMP err_endif_without_ifdef
.has_ifdef:
  ; Clear ELSE_SEEN_ARRAY entry for this depth before decrementing
  TAY                  ; Y = COND_DEPTH (use Y, not X!)
  LDA #$00
  STA ELSE_SEEN_ARRAY,Y
  DEC COND_DEPTH
  ; Check if this ends our skip block
  LDA SKIP_DEPTH
  BEQ .done            ; Not skipping, just decrement depth
  ; Currently skipping - check if we should stop
  LDA COND_DEPTH
  CMP SKIP_DEPTH
  BCS .done            ; Still in nested block (COND_DEPTH >= SKIP_DEPTH)
  ; COND_DEPTH < SKIP_DEPTH, stop skipping
  LDA #$00
  STA SKIP_DEPTH
.done:
  JMP skip_rest_of_line ; Tail call
