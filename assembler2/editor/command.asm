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
  JSR get_key

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
  JSR io_write
  JSR io_flush
  JMP .read_loop

.backspace:
  LDA CMD_IDX
  BEQ .cancel     ; Nothing to delete, cancel
  DEC CMD_IDX
  JSR erase_char
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
  LDA #':'
  JMP show_prompt

; Parse and execute the command in CMD_BUF
command_parse:
  LDA CMD_BUF

  ; :w - write
  CMP #'w'
  BEQ .check_w

  ; :q - quit
  CMP #'q'
  BEQ .check_q

  ; Try named commands (full string match from CMD_BUF[0])
  SET16 str_marks_cmd, STR_PTR16
  LDX #0
  JSR cmd_str_match
  BCC .do_marks

  ; Range/goto: ', ., or digit
  LDA CMD_BUF
  CMP #'\''
  BEQ .try_range
  CMP #'.'
  BEQ .try_range
  CMP #'0'
  BCC .unknown
  CMP #':'              ; '9'+1
  BCS .unknown
.try_range:
  JMP command_parse_range

.unknown:
  SET16 str_unknown_cmd, STR_PTR16
  JMP show_status_message

.do_marks:
  JMP marks_display

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
  JMP command_write_file

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

; Parse decimal number from CMD_BUF starting at offset X
; Returns: BUF_LEN16 = parsed number, X = updated offset past digits
;          carry clear = valid number, carry set = no digits found
; Clobbers: A, BUF_LEN16, BUF_SRC16
parse_decimal:
  SET16 $0000, BUF_LEN16
  STX CMD_IDX              ; Save start offset
.loop:
  LDA CMD_BUF,X
  SEC
  SBC #'0'
  BMI .done
  CMP #10
  BCS .done

  ; Multiply BUF_LEN16 by 10 and add digit
  PHA
  ASL16 BUF_LEN16
  CP16 BUF_LEN16, BUF_SRC16
  ASL16 BUF_LEN16
  ASL16 BUF_LEN16
  CLC
  ADC16 BUF_LEN16, BUF_SRC16, BUF_LEN16
  PLA
  CLC
  ADCA16 BUF_LEN16, BUF_LEN16

  INX
  JMP .loop
.done:
  CPX CMD_IDX
  BEQ .no_digits
  CLC
  RTS
.no_digits:
  SEC
  RTS

; Parse one range position starting at CMD_BUF[X]
; Handles: 'x (mark), . (current line), decimal number (1-based)
; Returns: BUF_LEN16 = 0-based line number, X = updated offset
;          carry clear = success, carry set = error
; Clobbers: A
parse_range_pos:
  LDA CMD_BUF,X
  CMP #'\''
  BEQ .mark
  CMP #'.'
  BEQ .dot
  ; Try decimal number
  JSR parse_decimal        ; BUF_LEN16 = number, X = updated offset
  BCS .error
  ; Convert 1-based to 0-based (0 stays at 0 = first line)
  TST16 BUF_LEN16
  BEQ .num_ok
  SEC
  SBCI16 BUF_LEN16, $0001, BUF_LEN16
  ; Clamp to LINE_COUNT16-1
  CMP16 BUF_LEN16, LINE_COUNT16
  BCC .num_ok
  SEC
  SBCI16 LINE_COUNT16, $0001, BUF_LEN16
.num_ok:
  CLC
  RTS
.mark:
  INX                     ; Skip quote
  LDA CMD_BUF,X
  INX                     ; Skip mark letter
  ; Save X (CMD_BUF offset), mark_get returns result in A/X
  STX CMD_IDX
  JSR mark_get            ; A = low, X = high, carry set if invalid
  BCS .error
  STA BUF_LEN16
  STX BUF_LEN16 + 1
  LDX CMD_IDX
  CLC
  RTS
.dot:
  INX                     ; Skip dot
  CP16 FILE_LINE16, BUF_LEN16
  CLC
  RTS
.error:
  SEC
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
  JSR io_write
  JSR write_fname
  LDA #'"'
  JSR io_write
  LDA #' '
  JSR io_write

  ; Print " written"
  PRINT_STR str_written

  JSR io_flush
  ; Brief pause to show message - wait for next redraw
  RTS

; Show "Buffer full" status message
show_buffer_full_msg:
  SET16 str_buffer_full, STR_PTR16
  JMP show_status_message

; Show a status message and wait for keypress
; STR_PTR16 must be set to the message string before calling
show_status_message:
  ; Save message pointer (command_show_prompt clobbers STR_PTR16)
  PUSH16 STR_PTR16
  JSR command_show_prompt
  POP16 STR_PTR16
  JSR write_string
  JSR io_flush
  JSR get_key
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

; Parse range or goto command
; Handles: :'a,.y  :'a,'bd  :1,3d  :1,.y  :.,'ay  :NNN (goto)
command_parse_range:
  LDX #0
  JSR parse_range_pos     ; Parse first position -> BUF_LEN16
  BCC .range_first_ok
  JMP .range_mark_err
.range_first_ok:
  CP16 BUF_LEN16, BUF_SRC16

  ; Check for comma (range) or end (goto)
  LDA CMD_BUF,X
  CMP #','
  BEQ .range_has_comma

  ; No comma: maybe :NNN goto
  CMP #0
  BEQ .range_goto
  JMP .range_unknown      ; Extra chars = unknown command

.range_goto:
  ; :NNN goto (BUF_SRC16 = 0-based line)
  CP16 BUF_SRC16, FILE_LINE16
  LDA #0
  STA_LH16 CURSOR_COL16
  JMP clamp_cursor_col

.range_has_comma:
  INX                     ; Skip comma
  PUSH16 BUF_SRC16        ; Save first position (parse_decimal clobbers BUF_SRC16)
  JSR parse_range_pos     ; Parse second position -> BUF_LEN16
  POP16 BUF_SRC16         ; PLA preserves carry on 6502
  BCC .range_second_ok
  JMP .range_mark_err
.range_second_ok:
  CP16 BUF_LEN16, BUF_DST16

  ; Get command char
  LDA CMD_BUF,X
  JMP .range_dispatch

.range_dispatch:
  ; A = command char
  STA CMD_IDX              ; Save command char
  CMP #'y'
  BEQ .range_action
  CMP #'d'
  BEQ .range_action
  JMP .range_unknown

.range_action:
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

  ; Copy full 16-bit count to BUF_TEMP16 (no 255 cap)
  CP16 BUF_LEN16, BUF_TEMP16

  ; Dispatch to yank or delete
  LDA CMD_IDX
  CMP #'d'
  BEQ .range_do_delete

  ; --- Range yank ---
  JSR yank_clear
  LDAX16 BUF_SRC16
  JSR yank_add_lines
  BCS .range_yank_full

  ; Show "N lines yanked"
  CP16 YANK_LINES16, TO_DECIMAL_VALUE16
  JSR to_decimal
  JSR command_show_prompt
  PRINT_STR TO_DECIMAL_RESULT
  PRINT_STR str_lines_yanked
  JSR io_flush
  RTS

.range_yank_full:
  JSR yank_clear
  SET16 str_yank_full, STR_PTR16
  JMP show_status_message

  ; --- Range delete ---
.range_do_delete:
  LDA READONLY
  BEQ .range_not_readonly
  SET16 str_readonly, STR_PTR16
  JMP show_status_message
.range_not_readonly:
  ; Yank lines first (so user can paste them back)
  ; Save first line (yank_add_lines clobbers BUF_SRC16)
  PUSH16 BUF_SRC16
  JSR yank_clear
  LDAX16 BUF_SRC16
  JSR yank_add_lines
  POP16 BUF_SRC16          ; PLA preserves carry on 6502
  BCS .range_yank_full

  ; Adjust marks before deletion (mark_adjust_delete clobbers BUF_SRC16/BUF_DST16)
  CP16 YANK_LINES16, BUF_TEMP16
  PUSH16 BUF_SRC16
  LDAX16 BUF_SRC16
  JSR mark_adjust_delete
  POP16 BUF_SRC16

  ; Delete lines (buf_delete_lines clobbers BUF_SRC16)
  CP16 YANK_LINES16, BUF_TEMP16
  PUSH16 BUF_SRC16
  LDAX16 BUF_SRC16
  JSR buf_delete_lines
  POP16 BUF_SRC16

  ; Move cursor to first deleted line position
  CP16 BUF_SRC16, FILE_LINE16

  ; Clamp cursor if past end of file
  CMP16 FILE_LINE16, LINE_COUNT16
  BCC .range_del_ok
  SEC
  SBCI16 LINE_COUNT16, $0001, FILE_LINE16
.range_del_ok:
  LDA #$FF
  STA RENDER_FLAG
  STA MODIFIED
  JSR clamp_cursor_col

  ; Show "N lines deleted"
  CP16 YANK_LINES16, TO_DECIMAL_VALUE16
  JSR to_decimal
  JSR command_show_prompt
  PRINT_STR TO_DECIMAL_RESULT
  PRINT_STR str_lines_deleted
  JSR io_flush
  RTS

.range_mark_err:
  SET16 str_mark_not_set, STR_PTR16
  JMP show_status_message

.range_unknown:
  SET16 str_unknown_cmd, STR_PTR16
  JMP show_status_message

str_lines_yanked:  .asciiz " lines yanked"
str_lines_deleted: .asciiz " lines deleted"
str_marks_cmd:     .asciiz "marks"

; === String constants ===
str_unknown_cmd: .asciiz "Unknown command"
str_no_write:    .asciiz "No write since last change (use :q! to override)"
str_written:     .asciiz "written"
str_buffer_full: .asciiz "Buffer full"
str_readonly:    .asciiz "Read-only (file truncated)"
str_truncated:   .asciiz "WARNING: File too large - read only"
str_yank_full:   .asciiz "Yank buffer full"
str_mark_not_set: .asciiz "Mark not set"
