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
  CMP #KEY_ESC
  BNE .not_esc
  JMP insert_exit
.not_esc:
  CMP #KEY_ENTER
  BNE .not_enter
  JMP insert_newline
.not_enter:
  CMP #KEY_BS
  BNE .not_bs
  JMP insert_backspace
.not_bs:

  ; Arrow keys
  CMP #KEY_UP
  BNE .not_up
  JMP insert_move_up
.not_up:
  CMP #KEY_DOWN
  BNE .not_down
  JMP insert_move_down
.not_down:
  CMP #KEY_LEFT
  BNE .not_left
  JMP insert_move_left
.not_left:
  CMP #KEY_RIGHT
  BNE .not_right
  JMP insert_move_right
.not_right:
  CMP #KEY_PGDN
  BNE .not_pgdn
  JMP insert_page_down
.not_pgdn:
  CMP #KEY_PGUP
  BNE .not_pgup
  JMP insert_page_up
.not_pgup:
  CMP #$06           ; Ctrl-F
  BNE .not_ctrl_f
  JMP insert_page_down
.not_ctrl_f:
  CMP #$02           ; Ctrl-B
  BNE .not_ctrl_b
  JMP insert_page_up
.not_ctrl_b:

  ; Printable character?
  CMP #' '
  BCC .ignore
  CMP #$7F
  BCS .ignore

  ; Insert printable character
  JMP insert_char

.ignore:
  RTS

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
  RTS

; Insert a printable character at cursor position
; Character in A
insert_char:
  STA BUF_TEMP

  ; Get pointer to current position in buffer
  LDA FILE_LINE16
  LDX FILE_LINE16 + 1
  JSR buf_get_line_ptr
  CLC
  LDA BUF_PTR16
  ADC CURSOR_COL
  STA BUF_PTR16
  LDA BUF_PTR16 + 1
  ADC #0
  STA BUF_PTR16 + 1

  LDA BUF_TEMP
  JSR buf_insert_char
  BCS .insert_char_full
  JSR buf_adjust_lines_inc

  INC CURSOR_COL
  LDA #1
  STA RENDER_FLAG
  LDA #$FF
  STA MODIFIED
  RTS
.insert_char_full:
  SET16 str_buffer_full, STR_PTR16
  JSR show_status_message
  RTS

; Insert newline at cursor (split line)
insert_newline:
  LDA FILE_LINE16
  LDX FILE_LINE16 + 1
  JSR buf_get_line_ptr
  CLC
  LDA BUF_PTR16
  ADC CURSOR_COL
  STA BUF_PTR16
  LDA BUF_PTR16 + 1
  ADC #0
  STA BUF_PTR16 + 1

  JSR buf_insert_newline
  BCS .insert_newline_full

  ; Move to start of next line
  INC16 FILE_LINE16
  LDA #0
  STA CURSOR_COL

  ; Scroll if needed
  LDA CURSOR_ROW
  CLC
  ADC #2
  CMP SCREEN_ROWS
  BCC .no_scroll
  INC16 VIEW_TOP16
  JMP .done
.no_scroll:
  INC CURSOR_ROW
.done:
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

  ; Delete character before cursor
  LDA FILE_LINE16
  LDX FILE_LINE16 + 1
  JSR buf_get_line_ptr
  CLC
  LDA BUF_PTR16
  ADC CURSOR_COL
  STA BUF_PTR16
  LDA BUF_PTR16 + 1
  ADC #0
  STA BUF_PTR16 + 1

  ; Point to character before cursor
  SEC
  LDA BUF_PTR16
  SBC #1
  STA BUF_PTR16
  LDA BUF_PTR16 + 1
  SBC #0
  STA BUF_PTR16 + 1

  JSR buf_delete_char
  JSR buf_adjust_lines_dec
  DEC CURSOR_COL
  LDA #1
  STA RENDER_FLAG
  LDA #$FF
  STA MODIFIED
  RTS

.join_lines:
  ; At column 0 - join with previous line
  LDA FILE_LINE16
  ORA FILE_LINE16 + 1
  BEQ .cant_join     ; Can't join at first line

  ; Get length of previous line (will become new cursor col)
  SEC
  LDA FILE_LINE16
  SBC #1
  TAY
  LDA FILE_LINE16 + 1
  SBC #0
  TAX
  TYA
  JSR buf_get_line_len
  STA CURSOR_COL

  ; Delete the newline at end of previous line
  SEC
  LDA FILE_LINE16
  SBC #1
  TAY
  LDA FILE_LINE16 + 1
  SBC #0
  TAX
  TYA
  JSR buf_get_line_ptr
  ; Find the newline
  LDY #0
.find_nl:
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .found_nl
  INY
  BNE .find_nl
.found_nl:
  TYA
  CLC
  ADC BUF_PTR16
  STA BUF_PTR16
  LDA #0
  ADC BUF_PTR16 + 1
  STA BUF_PTR16 + 1

  JSR buf_delete_char
  JSR buf_rebuild_lines

  ; Move to previous line
  DEC16 FILE_LINE16

  ; Adjust cursor row
  LDA CURSOR_ROW
  BNE .dec_row
  ; Need to scroll up
  DEC16 VIEW_TOP16
  JMP .joined
.dec_row:
  DEC CURSOR_ROW
.joined:
  LDA #$FF
  STA MODIFIED
.cant_join:
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
  DEC CURSOR_COL
.done:
  LDA #0
  STA RENDER_FLAG
  RTS

insert_move_right:
  JSR get_current_line_len
  CMP CURSOR_COL
  BCC .done
  BEQ .done
  INC CURSOR_COL
.done:
  LDA #0
  STA RENDER_FLAG
  RTS

; Clamp cursor for insert mode (can be one past end of line content)
clamp_cursor_col_insert:
  JSR get_current_line_len
  CMP CURSOR_COL
  BCS .ok
  STA CURSOR_COL
.ok:
  RTS
