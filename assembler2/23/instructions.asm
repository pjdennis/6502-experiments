; instructions.asm - PC management, instruction lookup/emission, operand parsing
;
; Provides: emit, update_pc, advance_pc_to_hex16, handle_reserve,
;           lookup_mnemonic, find_opcode_for_mode, emit_instruction,
;           handle_fwdref_mode, parse_operand
;
; Requires:
;   CURR_CHAR, HEX16, OPERAND16, PC16, PASS, IN_ZEROPAGE, IS_FWDREF, STARTED
;   read_char, read_token, skip_spaces, skip_rest_of_line, check_for_end_of_line
;   parse_value
;   select_instruction_hash_table, find_in_hash_instruction
;   add_forward_ref, check_forward_ref
;   write
;   err_* (opcode/operand/mode/value/branch/zeropage errors)

  .zeropage

ADDR_MODE:       .byte        ; Current addressing mode

  .code


; Emit value (pass 2 only) and increment PC
; On entry A contains the byte to emit
;          X contains the file handle to write to
; On exit A, X, Y are preserved
; TODO: Consolidate the PASS and IN_ZEROPAGE flags so that emit can
;       do a single check instead of two for suppression of output
emit:
  BIT IN_ZEROPAGE
  BMI .in_zeropage     ; If in zero page, handle separately
  ; Not in zero page - proceed with normal emit logic
  INC16 PC16
  BIT PASS
  BPL .skip            ; Skip writing during pass 1
  JMP write            ; Tail call
.skip:
  RTS
.in_zeropage:
  ; In zero page - check for overflow BEFORE incrementing
  ; If high byte already non-zero, we've already overflowed past $FF
  LDA PC16+$01
  BNE .overflow
  INC16 PC16           ; Safe to increment
  RTS                  ; No writing in zeropage
.overflow:
  JMP err_zeropage_overflow


; Fast forward the program counter
; On entry PC16 contains the current program counter
;          HEX16 contains the new PC value
; On exit
; Raises 'Cannot move PC backwards' error if attempting to move PC backwards
update_pc:
  BIT IN_ZEROPAGE
  BMI .no_fill         ; No fill or STARTED check in zeropage
  BIT STARTED
  BMI .started
  DEC STARTED
  BNE .no_fill         ; Always taken
.started:
  CMP16 HEX16, PC16
  BCC .less            ; HEX16 < PC16: error
  JMP advance_pc_to_hex16
.less:
  JMP err_cannot_move_pc_backwards
.no_fill:
  CP16 HEX16, PC16
  RTS


; Advance PC16 to the value in HEX16
; In .zeropage: sets PC, checks overflow
; In .code pass 1: just sets PC (no output)
; In .code pass 2: emits zero-fill bytes
; Caller must ensure HEX16 >= PC16
advance_pc_to_hex16:
  BIT IN_ZEROPAGE
  BMI .zp
  BIT PASS
  BPL .just_set        ; pass 1: just set PC
.loop:
  CMP16 HEX16, PC16
  BEQ .done
  LDA #$00
  JSR write
  INC PC16
  BNE .loop
  INC PC16+$01
  BNE .loop            ; Always taken
.done:
  RTS
.just_set:
  CP16 HEX16, PC16
  RTS
.zp:
  LDA HEX16+$01
  BNE .zp_overflow     ; Target > $FF
  CP16 HEX16, PC16
  RTS
.zp_overflow:
  JMP err_zeropage_overflow


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


; Look up mnemonic and save pointer to mode:opcode data
; On entry A contains the first character of the mnemonic
; On exit C = 0 if mnemonic or 1 if macro
;         CURR_CHAR contains the current character
;         If C = 0: INST_PTR16 points to mode:opcode data (past mnemonic)
;         X, Y are not preserved
; Raises 'Opcode not found' error if mnemonic is not found
lookup_mnemonic:
  JSR read_token       ; Current char in CURR_CHAR
  JSR select_instruction_hash_table
  JSR find_in_hash_instruction
  BCC .found
  JMP err_opcode_not_found
.found:
  ; TABP16 + Y points to mode:opcode data or macro sentinel
  ; Check for macro sentinel (MODE_MACRO)
  LDA (TABP16),Y
  CMP #MODE_MACRO
  BNE .is_instruction
  ; It's a macro - compute pointer to macro data and expand
  ; MACRO_DEF_PTR = TABP16 + Y + 1 (skip past MODE_MACRO to point at args)
  TYA
  SEC ; +1
  ADCA16 TABP16, MACRO_DEF_PTR16
  SEC                   ; Found macro usage
  RTS
.is_instruction:
  ; Calculate INST_PTR = TABP16 + Y
  TYA
  CLC
  ADCA16 TABP16, INST_PTR16
  CLC                   ; Found mnemonic
  RTS


; Find opcode for addressing mode in mode:opcode list
; On entry INST_PTR16 points to mode:opcode data
;          ADDR_MODE contains the addressing mode to find
; On exit C = 0 if found, A contains opcode
;         C = 1 if not found
;         X is preserved
;         Y is not preserved
find_opcode_for_mode:
  LDY #$00
.loop:
  LDA (INST_PTR16),Y  ; Get mode byte
  CMP #MODE_END
  BEQ .not_found      ; End of list, mode not found
  CMP ADDR_MODE
  BEQ .found
  ; Not this mode, skip to next pair
  INY
  INY
  BNE .loop           ; Always taken
.found:
  INY
  LDA (INST_PTR16),Y  ; Get opcode byte
  CLC
  RTS
.not_found:
  SEC
  RTS


; Emit instruction based on addressing mode
; On entry INST_PTR16 points to mode:opcode data
;          ADDR_MODE contains the addressing mode
;          OPERAND16 contains operand value (if applicable)
; On exit X is preserved
;         A, Y are not preserved
; Raises error if addressing mode is not valid for this instruction
emit_instruction:
  ; Find opcode for this addressing mode
  JSR find_opcode_for_mode
  BCS .invalid_mode
  ; Emit the opcode
  JSR emit
  ; Now emit operand(s) based on mode
  LDA ADDR_MODE
  CMP #MODE_NONE
  BEQ .done            ; No operand for implied mode
  CMP #MODE_REL
  BEQ .emit_relative   ; Relative needs special handling
  ; Check if 1-byte or 2-byte operand
  AND #OPERAND_BYTES_1
  BNE .one_byte
  ; 2-byte operand (absolute modes)
  LDA OPERAND16
  JSR emit
  LDA OPERAND16+$01
  JMP emit               ; Tail call
.done:
  RTS
.one_byte:
  ; Validate operand <= $FF
  BIT PASS
  BPL .one_byte_ok       ; Skip validation on pass 1
  LDA OPERAND16+$01
  BNE .one_byte_error
.one_byte_ok:
  LDA OPERAND16
  JMP emit                ; Tail call
.one_byte_error:
  JMP err_value_out_of_range
.emit_relative:
  ; Calculate relative offset: target - PC - 1
  BIT PASS
  BPL .emit_relative_pass1  ; Skip validation on pass 1
  CLC                  ; For the - 1
  LDA OPERAND16
  SBC PC16
  STA OPERAND16
  LDA OPERAND16+$01
  SBC PC16+$01
  ; Check if within range
  CMP #$00
  BEQ .forward
  CMP #$FF
  BEQ .backward
  JMP err_branch_out_of_range
.forward:
  LDA OPERAND16
  BPL .emit_relative_ok
  JMP err_branch_out_of_range
.backward:
  LDA OPERAND16
  BMI .emit_relative_ok
  JMP err_branch_out_of_range
.emit_relative_pass1:
  LDA OPERAND16
.emit_relative_ok:
  JMP emit                ; Tail call
.invalid_mode:
  JMP err_invalid_addressing_mode


; Checks mode availability, value size, and forward reference forcing
; On entry: ADDR_MODE set to ZP variant (MODE_ZP, MODE_ZPX, or MODE_ZPY)
;           INST_PTR16 points to instruction's mode:opcode data
;           OPERAND16 contains the operand value
;           IS_FWDREF set if operand is forward reference (pass 1)
;           PASS indicates current pass
; On exit: C=1 if must use ABS variant, C=0 if can use ZP variant
;          In pass 1 with forward ref: adds PC to forward ref list
;          In pass 2: consumes forward ref list entry if present
;          A, Y not preserved, X preserved
handle_fwdref_mode:
  JSR find_opcode_for_mode
  BCS .use_abs             ; No ZP mode available, must use ABS
  ; Check forward reference forcing (must be done before value check
  ; to properly consume forward ref entries in pass 2)
  BIT PASS
  BMI .pass2
  ; Pass 1 - check if this is a forward reference
  BIT IS_FWDREF
  BPL .check_value         ; Not a forward ref, check value size
  ; Forward ref in pass 1 - add to list, return C=1 (use ABS)
  JSR add_forward_ref
  SEC
  RTS
.pass2:
  ; Pass 2 - check the forward ref list
  JSR check_forward_ref    ; Returns C=1 if in list, C=0 if not
  BCS .use_abs             ; Was in list (forced to ABS), return C=1
.check_value:
  ; Check if value requires absolute addressing (>= $100)
  LDA OPERAND16+$01
  BNE .use_abs             ; Value >= $100, must use ABS
  ; Can use ZP
  CLC
  RTS
.use_abs:
  SEC
  RTS


; Parse operand and emit instruction
; On entry A contains the current character after mnemonic
;          INST_PTR16 points to mode:opcode data
; On exit OPERAND16 contains the operand value
;         ADDR_MODE contains the addressing mode
;         A, X, Y are not preserved
parse_operand:
  JSR check_for_end_of_line
  BCS .implied_mode    ; No operand = implied mode
  ; Check operand format to determine mode
  CMP #'('
  BEQ .indirect_mode
  CMP #'#'
  BNE .other_mode      ; Everything else: $xx $xxxx or label

.immediate_mode:
  ; #$xx or #<label or #>label or #label or #'x'
  JSR read_char        ; Skip #
  JSR parse_value      ; OPERAND16 set
  LDA #MODE_IMM
  STA ADDR_MODE
  RTS

.implied_mode:
  STA_LH16 OPERAND16
  LDA #MODE_NONE
  STA ADDR_MODE
  RTS

.indirect_mode:
  ; ($xx),Y - indirect indexed Y (1-byte operand)
  ; ($xx,X) - indirect indexed X (1-byte operand)
  ; ($xxxx) - indirect absolute for JMP (2-byte operand)
  JSR read_char        ; Skip (
  ; Parse value ($xx, <label, >label, or label)
  JSR parse_value      ; OPERAND16 set, current char in CURR_CHAR
  ; Check suffix to determine addressing mode
  LDA CURR_CHAR        ; Load current char (should be ) or ,)
  CMP #','
  BEQ .ind_x_mode
  ; Must be )
  CMP #')'
  BNE .ind_err_operand
  JSR read_char        ; Read char after )
  CMP #','
  BNE .ind_mode
  JSR read_char        ; Should be Y
  CMP #'Y'
  BNE .ind_err
; ind_y_mode
  JSR read_char        ; Read char after Y for garbage check
  LDA #MODE_INDY
  STA ADDR_MODE
  RTS

.ind_x_mode:
  JSR read_char        ; Should be X
  CMP #'X'
  BNE .ind_err
  JSR read_char        ; Should be )
  CMP #')'
  BNE .ind_err
  JSR read_char        ; Read char after ) for garbage check
  LDA #MODE_INDX
  STA ADDR_MODE
  RTS

.ind_mode:
  ; Just ($xxxx) - JMP indirect mode (must be 2-byte operand)
  ; Current char in CURR_CHAR (after ))
  LDA #MODE_IND
  STA ADDR_MODE
  RTS

.ind_err:
  JMP err_invalid_addressing_mode
.ind_err_operand:
  JMP err_invalid_operand

.other_mode:
  ; Parse value: $xx, $xxxx, or label
  ; All handled uniformly with appropriate mode selection
  JSR parse_value      ; Returns C=1 for bare label, OPERAND16 set, IS_FWDREF set, current char in CURR_CHAR
  ; Check if this is a branch instruction
  LDA #MODE_REL
  STA ADDR_MODE
  JSR find_opcode_for_mode ; Set C=0 if found (relative implies branch)
  BCC .relative_mode
  ; Not a branch - check for indexed mode
  LDA CURR_CHAR        ; Current char (might be comma)
  CMP #','
  BNE .non_index_mode
  ; Has index suffix - read X or Y
  JSR read_char
  CMP #'X'
  BEQ .x_index_mode
  CMP #'Y'
  BEQ .y_index_mode
  JMP err_invalid_addressing_mode

.relative_mode:
  ; MODE_REL already stored to ADDR_MODE
  RTS

.non_index_mode:
  ; Current char in CURR_CHAR
  LDA #MODE_ZP
  STA ADDR_MODE
  JSR handle_fwdref_mode   ; Checks mode availability, value size, forward refs
  BCS .abs_mode            ; Must use ABS
  ; Use ZP mode
  RTS

.abs_mode:
  LDA #MODE_ABS
  STA ADDR_MODE
  RTS

.x_index_mode:
  JSR read_char            ; Read char after X for garbage check, stores in CURR_CHAR
  LDA #MODE_ZPX
  STA ADDR_MODE
  JSR handle_fwdref_mode   ; Checks mode availability, value size, forward refs
  BCS .absx_index_mode     ; Must use ABSX
  ; Use ZPX mode
  RTS

.absx_index_mode:
  LDA #MODE_ABSX
  STA ADDR_MODE
  RTS

.y_index_mode:
  JSR read_char            ; Read char after Y for garbage check, stores in CURR_CHAR
  LDA #MODE_ZPY
  STA ADDR_MODE
  JSR handle_fwdref_mode   ; Checks mode availability, value size, forward refs
  BCS .absy_index_mode     ; Must use ABSY
  ; Use ZPY mode
  RTS

.absy_index_mode:
  LDA #MODE_ABSY
  STA ADDR_MODE
  RTS
