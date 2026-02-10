; Mark storage and operations
;
; Stores line-oriented marks (a-z) as 16-bit line numbers.
; Marks are stored in MARK_TBL at $E500 (52 bytes: 26 entries x 2 bytes).
; MARK_UNSET ($FFFF) indicates an unset mark.

MARK_TBL   = $E500    ; 26 entries x 2 bytes = 52 bytes
MARK_UNSET = $FFFF

  .code

; Initialize all 26 marks to MARK_UNSET ($FFFF)
mark_init:
  LDX #51              ; 26*2 - 1
  LDA #$FF
.loop:
  STA MARK_TBL,X
  DEX
  BPL .loop
  RTS

; Set mark: store current FILE_LINE16 at mark position
; Input: A = mark name ('a'-'z')
; Returns: carry set if invalid name, carry clear if set
mark_set:
  CMP #'a'
  BCC .invalid
  CMP #'{'             ; 'z'+1
  BCS .invalid
  SEC
  SBC #'a'
  ASL                  ; *2 for 16-bit entries
  TAX
  LDA FILE_LINE16
  STA MARK_TBL,X
  LDA FILE_LINE16 + 1
  STA MARK_TBL + 1,X
  CLC
  RTS
.invalid:
  SEC
  RTS

; Get mark: retrieve line number for mark
; Input: A = mark name ('a'-'z')
; Returns: A = low byte, X = high byte of line number
;          carry set if unset or invalid, carry clear if valid
mark_get:
  CMP #'a'
  BCC .invalid
  CMP #'{'             ; 'z'+1
  BCS .invalid
  SEC
  SBC #'a'
  ASL                  ; *2 for 16-bit entries
  TAX
  LDA MARK_TBL + 1,X
  CMP #$FF
  BNE .valid
  LDA MARK_TBL,X
  CMP #$FF
  BEQ .unset
.valid:
  LDA MARK_TBL,X
  PHA
  LDA MARK_TBL + 1,X
  TAX
  PLA
  CLC
  RTS
.unset:
.invalid:
  SEC
  RTS

; Display all set marks
; Clears screen, prints mark/line/text table, waits for keypress
; Sets RENDER_FLAG = $FF on return (full redraw)
marks_display:
  JSR ansi_clear_screen
  PRINT_STR str_marks_header

  LDA #0
  STA BUF_TEMP           ; Mark index (0-25)
  LDA #2
  STA ANSI_ROW           ; Start at row 2
  STA BUF_DELTA          ; Count of marks displayed (init 0 since row 2 != 0)
  LDA #0
  STA BUF_DELTA

.marks_loop:
  LDA BUF_TEMP
  ASL
  TAX

  ; Skip unset marks
  LDA MARK_TBL + 1,X
  CMP #$FF
  BNE .marks_set
  LDA MARK_TBL,X
  CMP #$FF
  BNE .marks_set
  JMP .marks_next
.marks_set:

  ; Save mark table offset on stack
  TXA
  PHA

  ; Position cursor
  LDA #1
  STA ANSI_COL
  JSR ansi_move_cursor

  ; Print " a" (mark letter)
  LDA #' '
  JSR write_b
  LDA BUF_TEMP
  CLC
  ADC #'a'
  JSR write_b

  ; Restore table offset, get line number
  PLA
  TAX
  LDA MARK_TBL,X
  STA TO_DECIMAL_VALUE16
  LDA MARK_TBL + 1,X
  STA TO_DECIMAL_VALUE16 + 1

  ; Save line for text lookup (before INC16 modifies it)
  PUSH16 TO_DECIMAL_VALUE16

  ; Print right-justified 1-based line number in 6-char field
  INC16 TO_DECIMAL_VALUE16
  JSR to_decimal
  JSR write_decimal_rjust

  ; Print 2 spaces before text
  LDA #' '
  JSR write_b
  LDA #' '
  JSR write_b

  ; Get saved line number, print text
  POP16 BUF_PTR16
  CMP16 BUF_PTR16, LINE_COUNT16
  BCS .marks_text_done
  LDAX16 BUF_PTR16
  JSR buf_get_line_ptr
  ; Compute text width limit: SCREEN_COLS - 10 (2 " a" + 6 number + 2 spaces)
  LDA SCREEN_COLS
  SEC
  SBC #10
  STA LINE_LEN
  LDY #0
.marks_text:
  CPY LINE_LEN
  BCS .marks_text_done
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .marks_text_done
  CMP #' '
  BCS .marks_text_ok
  LDA #' '
.marks_text_ok:
  JSR write_b
  INY
  JMP .marks_text
.marks_text_done:

  INC ANSI_ROW
  INC BUF_DELTA

  ; Check screen full
  LDA ANSI_ROW
  CLC
  ADC #1
  CMP SCREEN_ROWS
  BCS .marks_done_display

.marks_next:
  INC BUF_TEMP
  LDA BUF_TEMP
  CMP #26
  BEQ .marks_done_display
  JMP .marks_loop

.marks_done_display:
  LDA BUF_DELTA
  BNE .marks_wait
  LDA #2
  STA ANSI_ROW
  LDA #1
  STA ANSI_COL
  JSR ansi_move_cursor
  PRINT_STR str_no_marks

.marks_wait:
  JSR con_flush
  JSR input_read_byte
  LDA #$FF
  STA RENDER_FLAG
  RTS

; Print TO_DECIMAL_RESULT right-justified in a 6-character field
; Clobbers: A, X, Y
write_decimal_rjust:
  ; Count digits
  LDX #0
.count:
  LDA TO_DECIMAL_RESULT,X
  BEQ .pad
  INX
  JMP .count
.pad:
  ; Print (6 - X) spaces
  STX BUF_DELTA
  LDX #6
.pad_loop:
  CPX BUF_DELTA
  BEQ .print
  LDA #' '
  JSR write_b
  DEX
  JMP .pad_loop
.print:
  PRINT_STR TO_DECIMAL_RESULT
  RTS

str_marks_header: .asciiz "mark  line  text"
str_no_marks:     .asciiz "No marks set"

; Adjust marks after lines are deleted
; Input: A/X = first deleted line (16-bit low/high)
;        BUF_TEMP = count of deleted lines
; Marks on [first_line, first_line+count): unset
; Marks >= first_line+count: subtract count
; Clobbers: A, X, Y
mark_adjust_delete:
  ; Store first_line in BUF_SRC16
  STAX16 BUF_SRC16

  ; Compute end_line = first_line + count -> BUF_DST16
  CLC
  LDA BUF_SRC16
  ADC BUF_TEMP
  STA BUF_DST16
  LDA BUF_SRC16 + 1
  ADC #0
  STA BUF_DST16 + 1

  LDX #0               ; Index into MARK_TBL
.del_loop:
  ; Skip unset marks
  LDA MARK_TBL + 1,X
  CMP #$FF
  BNE .del_not_unset
  LDA MARK_TBL,X
  CMP #$FF
  BEQ .del_next
.del_not_unset:

  ; Compare mark >= end_line (BUF_DST16)?
  LDA MARK_TBL + 1,X
  CMP BUF_DST16 + 1
  BCC .del_check_range  ; mark_hi < end_hi -> mark < end
  BNE .del_subtract     ; mark_hi > end_hi -> mark >= end
  LDA MARK_TBL,X
  CMP BUF_DST16
  BCS .del_subtract     ; mark_lo >= end_lo -> mark >= end

.del_check_range:
  ; Mark < end_line. Is mark >= first_line (BUF_SRC16)?
  LDA MARK_TBL + 1,X
  CMP BUF_SRC16 + 1
  BCC .del_next         ; mark_hi < first_hi -> mark < first, skip
  BNE .del_unset        ; mark_hi > first_hi -> mark >= first, in range
  LDA MARK_TBL,X
  CMP BUF_SRC16
  BCC .del_next         ; mark_lo < first_lo -> skip
  ; mark >= first_line and mark < end_line: unset
.del_unset:
  LDA #$FF
  STA MARK_TBL,X
  STA MARK_TBL + 1,X
  JMP .del_next

.del_subtract:
  ; mark >= end_line: subtract count
  SEC
  LDA MARK_TBL,X
  SBC BUF_TEMP
  STA MARK_TBL,X
  LDA MARK_TBL + 1,X
  SBC #0
  STA MARK_TBL + 1,X

.del_next:
  INX
  INX
  CPX #52              ; 26 * 2
  BNE .del_loop
  RTS

; Adjust marks after lines are inserted
; Input: A/X = at_line (16-bit low/high), BUF_TEMP = count of inserted lines
; Marks >= at_line: add count
; Clobbers: A, X, Y
mark_adjust_insert:
  ; Store at_line in BUF_SRC16
  STAX16 BUF_SRC16

  LDX #0               ; Index into MARK_TBL
.ins_loop:
  ; Skip unset marks
  LDA MARK_TBL + 1,X
  CMP #$FF
  BNE .ins_not_unset
  LDA MARK_TBL,X
  CMP #$FF
  BEQ .ins_next
.ins_not_unset:

  ; Compare mark >= at_line (BUF_SRC16)?
  LDA MARK_TBL + 1,X
  CMP BUF_SRC16 + 1
  BCC .ins_next         ; mark_hi < at_hi -> skip
  BNE .ins_add          ; mark_hi > at_hi -> mark >= at_line
  LDA MARK_TBL,X
  CMP BUF_SRC16
  BCC .ins_next         ; mark_lo < at_lo -> skip
  ; mark >= at_line: add count
.ins_add:
  CLC
  LDA MARK_TBL,X
  ADC BUF_TEMP
  STA MARK_TBL,X
  LDA MARK_TBL + 1,X
  ADC #0
  STA MARK_TBL + 1,X

.ins_next:
  INX
  INX
  CPX #52              ; 26 * 2
  BNE .ins_loop
  RTS
