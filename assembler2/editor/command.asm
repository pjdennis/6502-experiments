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
CMD_IDX     .data $00   ; Current index into command buffer
CMD_QUIT    .data $00   ; Set to $FF when editor should quit

  .code

; Enter command mode - show prompt and read command
command_handle
  LDA #$00
  STA CMD_IDX

  ; Show ':' prompt on last line
  JSR command_show_prompt

.cmd_read_loop
  JSR input_read_byte

  CMP #KEY_ESC
  BEQ .cmd_cancel
  CMP #$1B
  BEQ .cmd_cancel
  CMP #KEY_ENTER
  BEQ .cmd_execute
  CMP #$0D
  BEQ .cmd_execute
  CMP #KEY_BS
  BEQ .cmd_backspace
  CMP #$7F
  BEQ .cmd_backspace

  ; Printable character?
  CMP #$20
  BCC .cmd_read_loop
  CMP #$7F
  BCS .cmd_read_loop

  ; Add to buffer
  LDX CMD_IDX
  CPX #CMD_BUF_LEN
  BCS .cmd_read_loop  ; Buffer full
  STA CMD_BUF,X
  INC CMD_IDX

  ; Echo character
  JSR write_b
  JSR con_flush
  JMP .cmd_read_loop

.cmd_backspace
  LDA CMD_IDX
  BEQ .cmd_cancel     ; Nothing to delete, cancel
  DEC CMD_IDX
  ; Erase character on screen: backspace, space, backspace
  LDA #$08
  JSR write_b
  LDA #' '
  JSR write_b
  LDA #$08
  JSR write_b
  JSR con_flush
  JMP .cmd_read_loop

.cmd_cancel
  LDA #MODE_NORMAL
  STA MODE
  RTS

.cmd_execute
  ; Null-terminate the command
  LDX CMD_IDX
  LDA #$00
  STA CMD_BUF,X

  ; Parse and execute
  JSR command_parse

  ; Return to normal mode (unless quitting)
  LDA CMD_QUIT
  BNE .stay
  LDA #MODE_NORMAL
  STA MODE
.stay
  RTS

; Show the ':' prompt on the status line
command_show_prompt
  LDA SCREEN_ROWS
  STA ANSI_ROW
  LDA #$01
  STA ANSI_COL
  JSR ansi_move_cursor
  JSR ansi_clear_line
  LDA #':'
  JSR write_b
  JSR con_flush
  RTS

; Parse and execute the command in CMD_BUF
command_parse
  LDA CMD_BUF

  ; :w - write
  CMP #'w'
  BEQ .check_w

  ; :q - quit
  CMP #'q'
  BEQ .check_q

  ; Digit - go to line
  CMP #'0'
  BCC .unknown
  CMP #':'          ; '9'+1 = ':'
  BCC .goto_line

.unknown
  SET16 str_unknown_cmd STR_PTR16
  JMP show_status_message

.check_w
  LDA READONLY
  BEQ .not_readonly_w
  SET16 str_readonly STR_PTR16
  JSR show_status_message
  RTS
.not_readonly_w
  LDA CMD_BUF+$01
  BEQ .do_write       ; Just ":w"
  CMP #'q'
  BEQ .check_wq
  JMP .unknown

.check_wq
  LDA CMD_BUF+$02
  BNE .unknown        ; Extra chars after ":wq"
  ; :wq - write and quit
  JSR command_write_file
  LDA #$FF
  STA CMD_QUIT
  RTS

.do_write
  JSR command_write_file
  RTS

.check_q
  LDA CMD_BUF+$01
  BEQ .do_quit        ; Just ":q"
  CMP #'!'
  BEQ .force_quit
  JMP .unknown

.do_quit
  ; Check if modified
  LDA MODIFIED
  BEQ .quit_ok
  ; Show warning
  SET16 str_no_write STR_PTR16
  JMP show_status_message

.quit_ok
  LDA #$FF
  STA CMD_QUIT
  RTS

.force_quit
  LDA CMD_BUF+$02
  BNE .unknown        ; Extra chars after ":q!"
  LDA #$FF
  STA CMD_QUIT
  RTS

; Go to line number
.goto_line
  ; Parse decimal number from CMD_BUF
  SET16 $0000 BUF_LEN16   ; Accumulator for line number
  LDX #$00

.parse_digit
  LDA CMD_BUF,X
  BEQ .goto_done
  SEC
  SBC #'0'
  BMI .bad_digit
  CMP #$0A
  BCS .bad_digit
  JMP .valid_digit
.bad_digit
  JMP .unknown
.valid_digit

  ; Multiply accumulator by 10: BUF_LEN16 = BUF_LEN16 * 10
  ; = BUF_LEN16 * 8 + BUF_LEN16 * 2
  PHA              ; save digit
  ; Save original
  CP16 BUF_LEN16 BUF_SRC16
  ; *2
  ASL16 BUF_LEN16
  ; *4
  ASL16 BUF_LEN16
  ; *8
  ASL16 BUF_LEN16
  ; + original*2
  CLC
  ASL BUF_SRC16
  ROL BUF_SRC16+$01
  CLC
  LDA BUF_LEN16
  ADC BUF_SRC16
  STA BUF_LEN16
  LDA BUF_LEN16+$01
  ADC BUF_SRC16+$01
  STA BUF_LEN16+$01

  ; Add digit
  PLA
  CLC
  ADC BUF_LEN16
  STA BUF_LEN16
  LDA #$00
  ADC BUF_LEN16+$01
  STA BUF_LEN16+$01

  INX
  JMP .parse_digit

.goto_done
  ; BUF_LEN16 = 1-based line number, convert to 0-based
  LDA BUF_LEN16
  ORA BUF_LEN16+$01
  BEQ .goto_ret      ; :0 does nothing

  SEC
  LDA BUF_LEN16
  SBC #$01
  STA FILE_LINE16
  LDA BUF_LEN16+$01
  SBC #$00
  STA FILE_LINE16+$01

  ; Clamp to last line
  LDA FILE_LINE16+$01
  CMP LINE_COUNT16+$01
  BCC .line_ok
  BNE .clamp_line
  LDA FILE_LINE16
  CMP LINE_COUNT16
  BCC .line_ok
.clamp_line
  SEC
  LDA LINE_COUNT16
  SBC #$01
  STA FILE_LINE16
  LDA LINE_COUNT16+$01
  SBC #$00
  STA FILE_LINE16+$01
.line_ok
  ; Set VIEW_TOP so cursor is near top of screen
  CP16 FILE_LINE16 VIEW_TOP16
  LDA #$00
  STA CURSOR_ROW
  STA CURSOR_COL
  JSR clamp_cursor_col
.goto_ret
  RTS

; Write (save) the file
command_write_file
  ; Open file for writing
  LDA FNAME_PTR16
  LDX FNAME_PTR16+$01
  JSR openout
  STA FILE_HANDLE

  ; Write buffer contents
  LDA FILE_HANDLE
  JSR buf_save_file

  ; Close file
  LDA FILE_HANDLE
  JSR close

  ; Clear modified flag
  LDA #$00
  STA MODIFIED

  ; Show confirmation on status line
  JSR command_show_prompt
  LDA #'"'
  JSR write_b
  LDY #$00
.print_fname
  LDA (FNAME_PTR16),Y
  BEQ .fname_done
  JSR write_b
  INY
  CPY #$20
  BCC .print_fname
.fname_done
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
show_status_message
  JSR command_show_prompt
  JSR write_string
  JSR con_flush
  JSR input_read_byte
  RTS

; === String constants ===
str_unknown_cmd .data "Unknown command" $00
str_no_write    .data "No write since last change (use :q! to override)" $00
str_written     .data "written" $00
str_buffer_full .data "Buffer full" $00
str_readonly    .data "Read-only (file truncated)" $00
str_truncated   .data "WARNING: File too large - read only" $00
