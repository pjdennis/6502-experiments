; expressions.asm - Expression evaluation, character literals, term parsing
;
; Provides: parse_char_literal, parse_term, parse_value,
;           apply_low_byte, apply_high_byte, parse_term_with_selector,
;           expr_next_term, parse_expression
;
; Requires:
;   CURR_CHAR (asm.asm alias; backing storage in source_stack.asm)
;   TOKEN, HEX16, OPERAND16, PASS, IS_FWDREF (asm.asm)
;   LABEL_TYPE, LABEL_TYPE_GLOBAL, LABEL_TYPE_MACRO (common.asm)
;   SCOPE_DEPTH (label_scope.asm)
;   read_char (asm.asm alias; implemented in source_stack.asm)
;   skip_spaces, compare_end_of_token, read_token, read_hex,
;   decode_escape (tokenizer.asm)
;   read_local_label (labels.asm)
;   select_label_hash_table (common.asm)
;   find_in_hash (hash_table.asm)
;   from_decimal (from_decimal.asm)
;   err_* (errors.asm)

  .zeropage

EXPR_ACCU16:     .word        ; Expression accumulator
EXPR_FWDREF:     .byte        ; Accumulated forward ref flag

  .code


; Resolve a global-style identifier (the token in TOKEN). When inside
; a macro expansion this tries the macro-local hash first so that
; parameters shadow same-named globals; otherwise (and on miss) it
; falls back to the global hash. Local-label (.foo) references skip
; this and go straight to the local-label path -- they're already
; scoped per macro invocation via LABEL_SCOPE16.
;
; Phase 4 will extend this chokepoint to consult the innermost macro
; frame's parameter slots before any hash lookup; for now it's the
; same logic that used to be inlined in parse_term, just in one place.
;
; On entry: TOKEN holds a null-terminated identifier; LABEL_TYPE = the
;           base type to use on the global path (typically
;           LABEL_TYPE_GLOBAL).
; On exit:  C=0 if found (HEX16 holds the value); C=1 if not found.
;           LABEL_TYPE is left as LABEL_TYPE_MACRO when the macro-local
;           lookup matched, otherwise restored to LABEL_TYPE_GLOBAL.
;           HASH / CACHED_HASH side-effects per find_in_hash.
;           A, X clobbered; Y not preserved.
resolve_identifier:
  ; Not in a macro expansion: just do the global lookup directly.
  LDA SCOPE_DEPTH
  BEQ .global
  ; In a macro: try the macro-local hash first.
  LDA #LABEL_TYPE_MACRO
  STA LABEL_TYPE
  JSR select_label_hash_table
  JSR find_in_hash
  BCC .done                 ; Found as parameter -- LABEL_TYPE = MACRO
  ; Macro-local miss; restore base type and fall through to global.
  LDA #LABEL_TYPE_GLOBAL
  STA LABEL_TYPE
.global:
  JSR select_label_hash_table
  JMP find_in_hash          ; tail call; preserves caller's C from us
.done:
  RTS


; Parse character literal: 'x' or escape sequences
; On entry: A contains the opening quote character '
; On exit: A contains current character (for garbage checking)
;          OPERAND16 contains character value
;          X is preserved
;          Y is not preserved
; Raises 'Invalid character literal' error on malformed input
parse_char_literal:
  JSR read_char        ; Skip opening quote
  CMP #'\''
  BEQ .char_invalid    ; Empty literal - error
  CMP #'\\'
  BEQ .char_escape
  CMP #'\n'
  BEQ .char_invalid    ; Newline without closing quote - error
  ; Regular character
  STA OPERAND16
  JMP .char_check_close
.char_escape:
  JSR read_char
  JSR decode_escape
  BCC .char_invalid
  STA OPERAND16
.char_check_close:
  JSR read_char        ; Should be closing quote
  CMP #'\''
  BNE .char_invalid
  LDA #$00
  STA OPERAND16 + 1
  ; Read char for garbage check
  JMP read_char        ; Tail call
.char_invalid:
  JMP err_invalid_char_literal


; Parse a term (single value): $12, $1234, 'x', label, <label, or >label
; On entry A contains first character
; On exit  CURR_CHAR contains current character
;          OPERAND16 contains parsed value
;          IS_FWDREF set if bare label was forward ref (pass 1 only)
;          X is preserved
;          Y is not preserved
parse_term:
  CMP #'$'
  BEQ .hex
  CMP #'\''
  BEQ .char_literal
  CMP #'.'
  BEQ .local_ref
  ; Check for decimal digit
  CMP #'0'
  BCC .not_decimal       ; < '0'
  CMP #'9' + 1
  BCC .decimal           ; >= '0' and <= '9'
.not_decimal:
  ; Global label path
  JSR compare_end_of_token
  BCS .token_present
  JMP err_label_expected
.token_present:
  JSR read_token       ; Current char now in CURR_CHAR
  LDA #LABEL_TYPE_GLOBAL
  STA LABEL_TYPE
  JSR resolve_identifier
  BCC .label_found
  JMP .label_not_found
.local_ref:
  JSR read_local_label
  JSR select_label_hash_table
  JSR find_in_hash
  BCC .label_found
.label_not_found:
  ; Label not found - check pass
  BIT PASS
  BMI .label_not_found_pass2
  ; Pass 1 - forward reference: use zero values
  LDA #$FF
  STA IS_FWDREF        ; Mark as forward reference
  LDA #$00
  STA_LH16 HEX16
  BEQ .label_store     ; Always taken
.label_not_found_pass2:
  JMP err_label_not_found
.label_found:
  ; Label found - clear forward ref flag
  LDA #$00
  STA IS_FWDREF
.label_store:
  ; OPERAND16 already set (aliased to HEX16)
  RTS
.hex:
  JSR read_char        ; Skip $
  JMP read_hex         ; Tail call; Stores in HEX16
.char_literal:
  JSR parse_char_literal
  ; Result in OPERAND16
  RTS
.decimal:
  JSR from_decimal     ; Result in FROM_DECIMAL16
  CP16 FROM_DECIMAL16, OPERAND16
  RTS


; Parse a value (expression with optional byte selector prefix)
; On entry: A contains first character
; On exit: CURR_CHAR contains current character
;          OPERAND16 contains result
;          IS_FWDREF set if expression contains forward ref (NOT set for byte selectors)
parse_value:
  CMP #'<'
  BEQ .low_byte_selector
  CMP #'>'
  BEQ .high_byte_selector
  JMP parse_expression

.low_byte_selector:
  JSR read_char        ; Skip '<'
  JSR skip_spaces
  JSR parse_expression ; Current char now in CURR_CHAR
  JMP apply_low_byte

.high_byte_selector:
  JSR read_char        ; Skip '>'
  JSR skip_spaces
  JSR parse_expression ; Current char now in CURR_CHAR
  JMP apply_high_byte


; Apply low byte selector: zero high byte and clear IS_FWDREF
apply_low_byte:
  LDA #$00
  STA OPERAND16 + 1
  STA IS_FWDREF
  RTS

; Apply high byte selector: move high byte to low, zero high byte, clear IS_FWDREF
apply_high_byte:
  LDA OPERAND16 + 1
  STA OPERAND16
  LDA #$00
  STA OPERAND16 + 1
  STA IS_FWDREF
  RTS


; Parse term with optional byte selector prefix
; Unlike parse_value, does NOT handle chained operators - only byte selectors
; Used for shift counts to ensure left-to-right evaluation of shifts
; On entry: A contains first character
; On exit: CURR_CHAR contains current character
;          OPERAND16 contains result
;          IS_FWDREF set if term is forward ref (NOT set for byte selectors)
parse_term_with_selector:
  CMP #'<'
  BEQ .low_byte_selector
  CMP #'>'
  BEQ .high_byte_selector
  JMP parse_term

.low_byte_selector:
  JSR read_char        ; Skip '<'
  JSR skip_spaces
  JSR parse_term       ; Current char now in CURR_CHAR
  JMP apply_low_byte

.high_byte_selector:
  JSR read_char        ; Skip '>'
  JSR skip_spaces
  JSR parse_term       ; Current char now in CURR_CHAR
  JMP apply_high_byte


; Save current operand, parse next term, accumulate forward ref flag
; Used by expression operator paths to avoid duplicating this sequence
; On exit: EXPR_ACCU16 contains the saved operand
;          OPERAND16 contains the new term
;          EXPR_FWDREF updated with IS_FWDREF
expr_next_term:
  CP16 OPERAND16, EXPR_ACCU16
  JSR read_char
  JSR skip_spaces
  JSR parse_term_with_selector
  LDA IS_FWDREF
  ORA EXPR_FWDREF
  STA EXPR_FWDREF
  RTS


; Parse expression: term [+|-|<<|>> term]*
; On entry: A contains first character
; On exit: CURR_CHAR contains current character
;          OPERAND16 contains result
;          IS_FWDREF set if any term is forward ref
parse_expression:
  JSR parse_term       ; Parse first term, current char in CURR_CHAR

  ; Save IS_FWDREF from first term
  LDA IS_FWDREF
  STA EXPR_FWDREF

.loop:
  ; Check << and >> before skipping spaces (< and > are ambiguous with byte selectors)
  LDA CURR_CHAR
  CMP #'<'
  BNE .not_lt
  JMP .check_left_shift
.not_lt:
  CMP #'>'
  BNE .not_gt
  JMP .check_right_shift
.not_gt:
  ; Check +, -, <<, >> after skipping spaces
  JSR skip_spaces
  CMP #'+'
  BEQ .add_op
  CMP #'-'
  BEQ .sub_op
  CMP #'<'
  BEQ .check_left_shift
  CMP #'>'
  BEQ .check_right_shift

  ; No more operators - restore and return
  LDA EXPR_FWDREF
  STA IS_FWDREF
  RTS

.add_op:
  JSR expr_next_term

  ; Add: accumulator + OPERAND -> OPERAND
  CLC
  ADC16 EXPR_ACCU16, OPERAND16, OPERAND16
  JMP .loop

.sub_op:
  JSR expr_next_term

  ; Subtract: accumulator - OPERAND -> OPERAND
  SEC
  SBC16 EXPR_ACCU16, OPERAND16, OPERAND16
  JMP .loop

.check_left_shift:
  ; Read char to confirm second '<'
  JSR read_char
  CMP #'<'
  BEQ .left_shift_op
  JMP err_expected_shift    ; Single '<' in middle of expression is error

.check_right_shift:
  ; Read char to confirm second '>'
  JSR read_char
  CMP #'>'
  BEQ .right_shift_op
  JMP err_expected_shift    ; Single '>' in middle of expression is error

.left_shift_op:
  JSR expr_next_term

  ; Check if shift count >= 16 (result will be 0)
  LDA OPERAND16 + 1
  BNE .shift_zero     ; High byte != 0 means shift >= 256
  LDA OPERAND16
  CMP #$10
  BCS .shift_zero     ; Low byte >= 16 means shift >= 16
  TAY                      ; Transfer shift count to Y

  ; Restore value to shift from EXPR_ACCU
  CP16 EXPR_ACCU16, OPERAND16

  ; Perform left shift
.left_shift_loop:
  DEY
  BMI .shift_done
  ASL16 OPERAND16
  JMP .left_shift_loop

.right_shift_op:
  JSR expr_next_term

  ; Check if shift count >= 16 (result will be 0)
  LDA OPERAND16 + 1
  BNE .shift_zero    ; High byte != 0 means shift >= 256
  LDA OPERAND16
  CMP #$10
  BCS .shift_zero    ; Low byte >= 16 means shift >= 16
  TAY                      ; Transfer shift count to Y

  ; Restore value to shift from EXPR_ACCU
  CP16 EXPR_ACCU16, OPERAND16

  ; Perform right shift (logical/unsigned)
.right_shift_loop:
  DEY
  BMI .shift_done
  LSR16 OPERAND16
  JMP .right_shift_loop

.shift_zero:
  ; Shift >= 16, result is 0
  LDA #$00
  STA_LH16 OPERAND16

.shift_done:
  JMP .loop
