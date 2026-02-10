; Insert mode handler
;
; In insert mode:
;   - Printable characters ($20-$7E) are inserted at cursor
;   - Enter ($0D) splits the line
;   - Backspace ($08) deletes char before cursor or joins lines
;   - ESC ($1B) returns to normal mode

  .code

; Handle a keystroke in insert mode
; Key code in A
insert_handle_key:
  STA BUF_TEMP
  LDA #<insert_keys
  LDX #>insert_keys
  JSR dispatch_key
  BCC .done
  ; Printable character?
  LDA BUF_TEMP
  CMP #' '
  BCC .done
  CMP #$7F
  BCS .done
  JMP insert_char
.done:
  RTS

; --- Dispatch table ---

insert_keys:
  .byte KEY_ESC
  .word insert_exit
  .byte KEY_ENTER
  .word insert_newline
  .byte KEY_BS
  .word insert_backspace
  .byte KEY_UP
  .word insert_move_up
  .byte KEY_DOWN
  .word insert_move_down
  .byte KEY_LEFT
  .word insert_move_left
  .byte KEY_RIGHT
  .word insert_move_right
  .byte KEY_PGDN
  .word insert_page_down
  .byte KEY_PGUP
  .word insert_page_up
  .byte $06              ; Ctrl-F
  .word insert_page_down
  .byte $02              ; Ctrl-B
  .word insert_page_up
  .byte 0                ; End sentinel

; Exit insert mode, return to normal mode
insert_exit:
  LDA #MODE_NORMAL
  STA MODE
  ; Move cursor back one per vi convention (unless at column 0)
  LDA CURSOR_COL
  BEQ .done
  DEC CURSOR_COL
.done:
  LDA #0
  STA RENDER_FLAG
  JSR ensure_cursor_visible
  RTS

; Insert a printable character at cursor position
; Character in A. Reads and batches any pending printable chars.
insert_char:
  ; Store first char in BATCH_BUF[0]
  STA BATCH_BUF
  LDX #1

  ; Read pending printable chars into BATCH_BUF[1..]
.batch_read:
  JSR input_ready
  CMP #$FF
  BNE .batch_apply
  JSR input_read_byte
  ; Check if printable ($20-$7E)
  CMP #' '
  BCC .batch_not_printable
  CMP #$7F
  BCS .batch_not_printable
  STA BATCH_BUF,X
  INX
  CPX #BATCH_MAX
  BNE .batch_read
  JMP .batch_apply

.batch_not_printable:
  JSR input_unread

.batch_apply:
  STX BUF_DELTA
  JSR get_cursor_buf_ptr
  JSR buf_insert_chars
  BCS .insert_char_full
  JSR buf_adjust_lines_inc

  ; Advance cursor by BUF_DELTA
  CLC
  LDA CURSOR_COL
  ADC BUF_DELTA
  STA CURSOR_COL

  LDA #1
  STA RENDER_FLAG
  JSR ensure_cursor_visible
  LDA #$FF
  STA MODIFIED
  RTS
.insert_char_full:
  SET16 str_buffer_full, STR_PTR16
  JSR show_status_message
  RTS

; Insert newline(s) at cursor (split line, batch pending Enter keys)
insert_newline:
  ; Count pending Enter keys, add 1 for current
  LDA #KEY_ENTER
  STA BUF_TEMP
  JSR count_pending_key      ; X = pending Enter count
  INX                        ; +1 for current key

  ; Fill BATCH_BUF with X newline ($0A) bytes
  STX BUF_DELTA
  LDY #0
  LDA #'\n'
.enter_fill:
  STA BATCH_BUF,Y
  INY
  CPY BUF_DELTA
  BNE .enter_fill

  ; Insert at current cursor position
  JSR get_cursor_buf_ptr
  JSR buf_insert_chars
  BCS .insert_newline_full

  ; Rebuild line table (one rebuild for entire batch)
  JSR buf_rebuild_lines

  ; Adjust marks: BUF_DELTA lines inserted at FILE_LINE16+1
  LDA BUF_DELTA
  STA BUF_TEMP
  CLC
  ADCI16 FILE_LINE16, $0001, BUF_DST16
  LDAX16 BUF_DST16
  JSR mark_adjust_insert

  ; Advance FILE_LINE16 by BUF_DELTA
  CLC
  LDA FILE_LINE16
  ADC BUF_DELTA
  STA FILE_LINE16
  LDA FILE_LINE16 + 1
  ADC #0
  STA FILE_LINE16 + 1

  LDA #0
  STA CURSOR_COL
  JSR ensure_cursor_visible
  LDA #$FF
  STA MODIFIED
  RTS
.insert_newline_full:
  SET16 str_buffer_full, STR_PTR16
  JSR show_status_message
  RTS

; Handle backspace in insert mode
insert_backspace:
  ; If at column 0, join with previous line
  LDA CURSOR_COL
  BEQ .join_lines

  ; Count pending BS keys inline, capped at CURSOR_COL
  ; Start with 1 for the current BS key
  LDX #1
.count_loop:
  CPX CURSOR_COL
  BEQ .count_done         ; At cap, stop
  JSR input_ready
  CMP #$FF
  BNE .count_done
  JSR input_read_byte
  CMP #KEY_BS
  BEQ .count_match
  CMP #$7F
  BEQ .count_match
  ; Not backspace, push back and stop
  JSR input_unread
  JMP .count_done
.count_match:
  INX
  CPX #BATCH_MAX
  BNE .count_loop
.count_done:

  STX BUF_DELTA
  ; Update cursor: CURSOR_COL -= BUF_DELTA
  SEC
  LDA CURSOR_COL
  SBC BUF_DELTA
  STA CURSOR_COL
  ; Get buffer pointer at new cursor position
  JSR get_cursor_buf_ptr
  ; Delete BUF_DELTA chars
  JSR buf_delete_chars
  JSR buf_adjust_lines_dec

  LDA #1
  STA RENDER_FLAG
  JSR ensure_cursor_visible
  LDA #$FF
  STA MODIFIED
  RTS

.join_lines:
  ; At column 0 - join with previous line
  TST16 FILE_LINE16
  BNE .can_join
  RTS                      ; Can't join at first line
.can_join:

  ; Get previous line length -> CURSOR_COL
  SEC
  SBCI16 FILE_LINE16, $0001, BUF_LEN16
  LDAX16 BUF_LEN16
  JSR buf_get_line_len
  STA CURSOR_COL

  ; Point BUF_PTR16 to the newline ending the previous line
  LDAX16 BUF_LEN16
  JSR buf_get_line_ptr
  LDY CURSOR_COL
  TYA
  CLC
  ADCA16 BUF_PTR16, BUF_PTR16

  ; X = count of newlines to delete (starts at 1 for the first join)
  LDX #1

  ; If previous line has content, skip batch scan
  LDA CURSOR_COL
  BNE .apply

  ; Previous line empty - scan backwards for consecutive \n bytes
.scan_loop:
  ; Check if BUF_PTR16 is at TEXT_BUF (buffer start)
  LDA BUF_PTR16
  CMP #<TEXT_BUF
  BNE .not_start
  LDA BUF_PTR16 + 1
  CMP #>TEXT_BUF
  BEQ .apply           ; At buffer start, stop
.not_start:

  ; Check byte before BUF_PTR16
  SEC
  LDA BUF_PTR16
  SBC #1
  STA BUF_SRC16
  LDA BUF_PTR16 + 1
  SBC #0
  STA BUF_SRC16 + 1
  LDY #0
  LDA (BUF_SRC16),Y
  CMP #'\n'
  BNE .apply           ; Line above has content, stop

  ; BUF_SRC16 points to a \n. Verify this \n ends an EMPTY line.
  ; Empty if BUF_SRC16 is at buffer start, or byte before it is also \n.
  LDA BUF_SRC16
  CMP #<TEXT_BUF
  BNE .check_prev
  LDA BUF_SRC16 + 1
  CMP #>TEXT_BUF
  BEQ .line_empty      ; First byte of buffer, just \n → empty

.check_prev:
  ; Check byte at BUF_SRC16 - 1 using BUF_LEN16 as temp
  SEC
  LDA BUF_SRC16
  SBC #1
  STA BUF_LEN16
  LDA BUF_SRC16 + 1
  SBC #0
  STA BUF_LEN16 + 1
  LDY #0
  LDA (BUF_LEN16),Y
  CMP #'\n'
  BNE .apply           ; Byte before is not \n → content line → stop

.line_empty:

  ; Read one BS key from input
  STX BUF_TEMP
  JSR input_ready
  CMP #$FF
  BNE .restore_x
  JSR input_read_byte
  CMP #KEY_BS
  BEQ .match
  CMP #$7F
  BEQ .match
  ; Not backspace, push back and stop
  JSR input_unread
  LDX BUF_TEMP
  JMP .apply
.match:
  LDX BUF_TEMP
  INX
  CPX #BATCH_MAX
  BEQ .apply
  ; Move BUF_PTR16 back one byte
  CP16 BUF_SRC16, BUF_PTR16
  JMP .scan_loop
.restore_x:
  LDX BUF_TEMP

.apply:
  STX BUF_DELTA
  JSR buf_delete_chars

  ; Subtract BUF_DELTA from FILE_LINE16
  SEC
  LDA FILE_LINE16
  SBC BUF_DELTA
  STA FILE_LINE16
  LDA FILE_LINE16 + 1
  SBC #0
  STA FILE_LINE16 + 1

  JSR buf_rebuild_lines

  ; Adjust marks: BUF_DELTA lines deleted at FILE_LINE16+1
  LDA BUF_DELTA
  STA BUF_TEMP
  CLC
  ADCI16 FILE_LINE16, $0001, BUF_DST16
  LDAX16 BUF_DST16
  JSR mark_adjust_delete

  JSR ensure_cursor_visible
  LDA #$FF
  STA MODIFIED
  RTS

; Arrow key handlers in insert mode
insert_move_up:
  JSR normal_move_up
  JSR clamp_cursor_col_insert
  RTS

insert_move_down:
  JSR normal_move_down
  JSR clamp_cursor_col_insert
  RTS

insert_page_down:
  JSR normal_page_down
  JSR clamp_cursor_col_insert
  RTS

insert_page_up:
  JSR normal_page_up
  JSR clamp_cursor_col_insert
  RTS

insert_move_left:
  LDA CURSOR_COL
  BEQ .done
  LDA #0
  STA RENDER_FLAG
  DEC CURSOR_COL
  JSR ensure_cursor_visible
.done:
  RTS

insert_move_right:
  JSR get_current_line_len
  CMP CURSOR_COL
  BCC .done
  BEQ .done
  LDA #0
  STA RENDER_FLAG
  INC CURSOR_COL
  JSR ensure_cursor_visible
.done:
  RTS

; Clamp cursor for insert mode (can be one past end of line content)
clamp_cursor_col_insert:
  JSR get_current_line_len
  CMP CURSOR_COL
  BCS .ok
  STA CURSOR_COL
.ok:
  RTS
