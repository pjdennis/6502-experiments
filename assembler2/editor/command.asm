; Command mode handler
;
; Commands:
;   :w       - save file
;   :q       - quit (warn if modified)
;   :wq      - save and quit
;   :q!      - quit without saving
;   :NNN     - go to line NNN

CMD_BUF     = $0300   ; Command buffer (256 bytes)
CMD_BUF_LEN = $00FF   ; Max command length

  .zeropage
CMD_IDX:     .byte     ; Current index into command buffer
CMD_QUIT:    .byte     ; Set to $FF when editor should quit

  .code

; Enter command mode - show prompt and read command
command_handle:
  LDA #0
  STA CMD_IDX

  ; Show ':' prompt on last line
  JSR command_show_prompt

.read_loop:
  JSR input_read_byte

  CMP #KEY_ESC
  BEQ .cancel
  CMP #$1B
  BEQ .cancel
  CMP #KEY_ENTER
  BEQ .execute
  CMP #'\r'
  BEQ .execute
  CMP #KEY_BS
  BEQ .backspace
  CMP #$7F
  BEQ .backspace

  ; Printable character?
  CMP #' '
  BCC .read_loop
  CMP #$7F
  BCS .read_loop

  ; Add to buffer
  LDX CMD_IDX
  CPX #CMD_BUF_LEN
  BCS .read_loop  ; Buffer full
  STA CMD_BUF,X
  INC CMD_IDX

  ; Echo character
  JSR write_b
  JSR con_flush
  JMP .read_loop

.backspace:
  LDA CMD_IDX
  BEQ .cancel     ; Nothing to delete, cancel
  DEC CMD_IDX
  ; Erase character on screen: backspace, space, backspace
  LDA #'\b'
  JSR write_b
  LDA #' '
  JSR write_b
  LDA #'\b'
  JSR write_b
  JSR con_flush
  JMP .read_loop

.cancel:
  LDA #MODE_NORMAL
  STA MODE
  RTS

.execute:
  ; Null-terminate the command
  LDX CMD_IDX
  LDA #0
  STA CMD_BUF,X

  ; Parse and execute
  JSR command_parse

  ; Return to normal mode (unless quitting)
  LDA CMD_QUIT
  BNE .stay
  LDA #MODE_NORMAL
  STA MODE
.stay:
  RTS

; Show the ':' prompt on the status line
command_show_prompt:
  LDA SCREEN_ROWS
  STA ANSI_ROW
  LDA #1
  STA ANSI_COL
  JSR ansi_move_cursor
  JSR ansi_clear_line
  LDA #':'
  JSR write_b
  JSR con_flush
  RTS

; Parse and execute the command in CMD_BUF
command_parse:
  LDA CMD_BUF

  ; :w - write
  CMP #'w'
  BEQ .check_w

  ; :q - quit
  CMP #'q'
  BEQ .check_q

  ; Digit - go to line
  CMP #'0'
  BCC .not_digit
  CMP #':'          ; '9'+1 = ':'
  BCS .not_digit
  JMP .goto_line
.not_digit:

  ; :marks - display marks
  CMP #'m'
  BEQ .check_marks

  ; :'a range commands
  CMP #'\''
  BNE .unknown
  JMP command_parse_range

.unknown:
  SET16 str_unknown_cmd, STR_PTR16
  JMP show_status_message

.check_w:
  LDA READONLY
  BEQ .not_readonly_w
  SET16 str_readonly, STR_PTR16
  JSR show_status_message
  RTS
.not_readonly_w:
  LDA CMD_BUF + 1
  BEQ .do_write       ; Just ":w"
  CMP #'q'
  BEQ .check_wq
  JMP .unknown

.check_wq:
  LDA CMD_BUF + 2
  BNE .unknown        ; Extra chars after ":wq"
  ; :wq - write and quit
  JSR command_write_file
  LDA #$FF
  STA CMD_QUIT
  RTS

.do_write:
  JSR command_write_file
  RTS

.check_q:
  LDA CMD_BUF + 1
  BEQ .do_quit        ; Just ":q"
  CMP #'!'
  BEQ .force_quit
  JMP .unknown

.do_quit:
  ; Check if modified
  LDA MODIFIED
  BEQ .quit_ok
  ; Show warning
  SET16 str_no_write, STR_PTR16
  JMP show_status_message

.quit_ok:
  LDA #$FF
  STA CMD_QUIT
  RTS

.force_quit:
  LDA CMD_BUF + 2
  BNE .unknown        ; Extra chars after ":q!"
  LDA #$FF
  STA CMD_QUIT
  RTS

.check_marks:
  SET16 str_marks_cmd, STR_PTR16
  LDX #1                  ; Compare from CMD_BUF+1 (after 'm')
  JSR cmd_str_match
  BCS .marks_unknown
  JMP marks_display
.marks_unknown:
  JMP .unknown

; Go to line number
.goto_line:
  ; Parse decimal number from CMD_BUF
  SET16 $0000, BUF_LEN16   ; Accumulator for line number
  LDX #0

.parse_digit:
  LDA CMD_BUF,X
  BEQ .goto_done
  SEC
  SBC #'0'
  BMI .bad_digit
  CMP #10
  BCS .bad_digit
  JMP .valid_digit
.bad_digit:
  JMP .unknown
.valid_digit:

  ; Multiply accumulator by 10: BUF_LEN16 = BUF_LEN16 * 10
  ; = BUF_LEN16 * 8 + BUF_LEN16 * 2
  PHA              ; save digit
  ; Original * 2
  ASL16 BUF_LEN16
  ; Save Original * 2
  CP16 BUF_LEN16, BUF_SRC16
  ; Original * 4
  ASL16 BUF_LEN16
  ; Original * 8
  ASL16 BUF_LEN16
  ; + original * 2
  CLC
  ADC16 BUF_LEN16, BUF_SRC16, BUF_LEN16

  ; Add digit
  PLA
  CLC
  ADCA16 BUF_LEN16, BUF_LEN16

  INX
  JMP .parse_digit

.goto_done:
  ; BUF_LEN16 = 1-based line number, convert to 0-based
  TST16 BUF_LEN16
  BEQ .goto_ret      ; :0 does nothing

  SEC
  SBCI16 BUF_LEN16, $0001, FILE_LINE16

  ; Clamp to last line
  CMP16 FILE_LINE16, LINE_COUNT16
  BCC .line_ok
  SEC
  SBCI16 LINE_COUNT16, $0001, FILE_LINE16
.line_ok:
  LDA #0
  STA CURSOR_COL
  JSR ensure_cursor_visible
  JSR clamp_cursor_col
.goto_ret:
  RTS

; Write (save) the file
command_write_file:
  ; Open file for writing
  LDAX16 FNAME_PTR16
  JSR openout
  STA FILE_HANDLE

  ; Write buffer contents
  LDA FILE_HANDLE
  JSR buf_save_file

  ; Close file
  LDA FILE_HANDLE
  JSR close

  ; Clear modified flag
  LDA #0
  STA MODIFIED

  ; Show confirmation on status line
  JSR command_show_prompt
  LDA #'"'
  JSR write_b
  JSR write_fname
  LDA #'"'
  JSR write_b
  LDA #' '
  JSR write_b

  ; Print " written"
  PRINT_STR str_written

  JSR con_flush
  ; Brief pause to show message - wait for next redraw
  RTS

; Show a status message and wait for keypress
; STR_PTR16 must be set to the message string before calling
show_status_message:
  ; Save message pointer (command_show_prompt clobbers STR_PTR16)
  PUSH16 STR_PTR16
  JSR command_show_prompt
  POP16 STR_PTR16
  JSR write_string
  JSR con_flush
  JSR input_read_byte
  RTS

; Compare CMD_BUF (starting at offset X) against asciiz string at STR_PTR16
; Input: X = starting offset in CMD_BUF, STR_PTR16 = string to match
; Returns: carry clear = match, carry set = no match
; Clobbers: A, X, Y
cmd_str_match:
  LDY #0
.loop:
  LDA (STR_PTR16),Y
  BEQ .check_end
  CMP CMD_BUF,X
  BNE .no_match
  INX
  INY
  JMP .loop
.check_end:
  LDA CMD_BUF,X
  BNE .no_match
  CLC
  RTS
.no_match:
  SEC
  RTS

; Parse range command: :'a,.y or :'a,'by etc.
; CMD_BUF contains the command starting with '
command_parse_range:
  ; Parse first mark: CMD_BUF[1] should be a-z
  LDA CMD_BUF + 1
  JSR mark_get
  BCC .range_first_ok
  JMP .range_mark_err
.range_first_ok:
  STAX16 BUF_SRC16         ; BUF_SRC16 = first line (start)

  ; Expect comma at CMD_BUF[2]
  LDA CMD_BUF + 2
  CMP #','
  BEQ .range_has_comma
  JMP .range_unknown
.range_has_comma:

  ; Parse second position: CMD_BUF[3]
  LDA CMD_BUF + 3
  CMP #'.'
  BEQ .range_dot
  CMP #'\''
  BEQ .range_second_mark
  JMP .range_unknown

.range_dot:
  ; Current line
  CP16 FILE_LINE16, BUF_DST16
  ; Command char at CMD_BUF[4]
  LDA CMD_BUF + 4
  JMP .range_dispatch

.range_second_mark:
  ; CMD_BUF[4] = mark name
  LDA CMD_BUF + 4
  JSR mark_get
  BCC .range_second_ok
  JMP .range_mark_err
.range_second_ok:
  STAX16 BUF_DST16
  ; Command char at CMD_BUF[5]
  LDA CMD_BUF + 5
  JMP .range_dispatch

.range_dispatch:
  ; A = command char
  CMP #'y'
  BEQ .range_yank
  JMP .range_unknown

.range_yank:
  ; Ensure start <= end (swap if needed)
  CMP16 BUF_SRC16, BUF_DST16
  BCC .range_order_ok
  BEQ .range_order_ok
  ; Swap BUF_SRC16 and BUF_DST16
  LDA BUF_SRC16
  PHA
  LDA BUF_DST16
  STA BUF_SRC16
  PLA
  STA BUF_DST16
  LDA BUF_SRC16 + 1
  PHA
  LDA BUF_DST16 + 1
  STA BUF_SRC16 + 1
  PLA
  STA BUF_DST16 + 1
.range_order_ok:

  ; count = end - start + 1
  SEC
  SBC16 BUF_DST16, BUF_SRC16, BUF_LEN16
  INC16 BUF_LEN16

  ; Cap count at 255 for yank_add_lines
  LDA BUF_LEN16 + 1
  BNE .range_cap
  LDA BUF_LEN16
  JMP .range_count_ok
.range_cap:
  LDA #$FF
.range_count_ok:
  STA BUF_TEMP

  JSR yank_clear
  LDAX16 BUF_SRC16
  JSR yank_add_lines
  BCS .range_yank_full

  ; Show "N lines yanked"
  LDA YANK_LINES
  STA TO_DECIMAL_VALUE16
  LDA #0
  STA TO_DECIMAL_VALUE16 + 1
  JSR to_decimal
  JSR command_show_prompt
  PRINT_STR TO_DECIMAL_RESULT
  PRINT_STR str_lines_yanked
  JSR con_flush
  RTS

.range_yank_full:
  JSR yank_clear
  SET16 str_yank_full, STR_PTR16
  JMP show_status_message

.range_mark_err:
  SET16 str_mark_not_set, STR_PTR16
  JMP show_status_message

.range_unknown:
  SET16 str_unknown_cmd, STR_PTR16
  JMP show_status_message

str_lines_yanked: .asciiz " lines yanked"
str_marks_cmd:    .asciiz "arks"

; === String constants ===
str_unknown_cmd: .asciiz "Unknown command"
str_no_write:    .asciiz "No write since last change (use :q! to override)"
str_written:     .asciiz "written"
str_buffer_full: .asciiz "Buffer full"
str_readonly:    .asciiz "Read-only (file truncated)"
str_truncated:   .asciiz "WARNING: File too large - read only"
str_yank_full:   .asciiz "Yank buffer full"
str_mark_not_set: .asciiz "Mark not set"
