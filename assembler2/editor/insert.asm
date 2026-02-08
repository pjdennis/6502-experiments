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

; Insert newline at cursor (split line)
insert_newline:
  JSR get_cursor_buf_ptr

  JSR buf_insert_newline
  BCS .insert_newline_full

  ; Move to start of next line
  INC16 FILE_LINE16
  LDA #0
  STA CURSOR_COL
  JSR enter_batch_pending
  JSR ensure_cursor_visible
  LDA #$FF
  STA MODIFIED
  RTS
.insert_newline_full:
  SET16 str_buffer_full, STR_PTR16
  JSR show_status_message
  RTS

; Batch-insert pending Enter keys after first newline was inserted.
; Counts buffered Enter keys, fills BATCH_BUF with $0A bytes,
; and inserts them all with one buf_insert_chars + buf_rebuild_lines.
enter_batch_pending:
  ; Count pending Enter keys
  LDA #KEY_ENTER
  STA BUF_TEMP
  JSR count_pending_key
  CPX #0
  BEQ .enter_batch_done

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
  BCS .enter_batch_done       ; Buffer full, skip batch

  ; Add BUF_DELTA to FILE_LINE16 (16-bit add)
  CLC
  LDA FILE_LINE16
  ADC BUF_DELTA
  STA FILE_LINE16
  LDA FILE_LINE16 + 1
  ADC #0
  STA FILE_LINE16 + 1

  ; Rebuild line table (one rebuild for entire batch)
  JSR buf_rebuild_lines

.enter_batch_done:
  RTS

; Handle backspace in insert mode
insert_backspace:
  ; If at column 0, join with previous line
  LDA CURSOR_COL
  BEQ .join_lines

  ; Count pending BS keys inline, capped at CURSOR_COL
  ; Start with 1 for the current BS key
  LDX #1
.bs_count_loop:
  CPX CURSOR_COL
  BEQ .bs_count_done         ; At cap, stop
  JSR input_ready
  CMP #$FF
  BNE .bs_count_done
  JSR input_read_byte
  CMP #KEY_BS
  BEQ .bs_count_match
  CMP #$7F
  BEQ .bs_count_match
  ; Not backspace, push back and stop
  JSR input_unread
  JMP .bs_count_done
.bs_count_match:
  INX
  CPX #BATCH_MAX
  BNE .bs_count_loop
.bs_count_done:

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
  BEQ .cant_join     ; Can't join at first line

  ; Compute previous line number once
  SEC
  SBCI16 FILE_LINE16, $0001, BUF_LEN16

  ; Get length of previous line (will become new cursor col)
  LDAX16 BUF_LEN16
  JSR buf_get_line_len
  STA CURSOR_COL

  ; Delete the newline at end of previous line
  LDAX16 BUF_LEN16
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
  ADCA16 BUF_PTR16, BUF_PTR16

  JSR buf_delete_char
  JSR buf_rebuild_lines

  ; Move to previous line
  DEC16 FILE_LINE16
  JSR joinlines_batch_pending
  JSR ensure_cursor_visible
  LDA #$FF
  STA MODIFIED
.cant_join:
  RTS

; Batch join-lines: consume pending backspace keys that join empty lines above.
; Called after first join-lines completed. CURSOR_COL has the length of the
; previous line (from the first join). We only batch when CURSOR_COL == 0
; (the previous line was empty) and there are empty lines above to join.
; Unlike count_pending_key, we read one BS at a time, checking buffer state
; each iteration, to avoid consuming BS keys we can't handle.
joinlines_batch_pending:
  ; Only batch if cursor is at col 0 (previous line was empty)
  LDA CURSOR_COL
  BEQ .jl_batch_start
  RTS
.jl_batch_start:

  ; Get current line start pointer
  JSR get_cursor_buf_ptr

  ; X = count of additional joins
  LDX #0

.jl_batch_loop:
  ; Check if FILE_LINE16 - X > 0 (still lines above)
  ; Compute FILE_LINE16 - X - 1
  SEC
  LDA FILE_LINE16
  SBC #1
  STA BUF_LEN16
  LDA FILE_LINE16 + 1
  SBC #0
  STA BUF_LEN16 + 1
  ; Subtract X
  SEC
  LDA BUF_LEN16
  STX BUF_TEMP
  SBC BUF_TEMP
  STA BUF_LEN16
  LDA BUF_LEN16 + 1
  SBC #0
  STA BUF_LEN16 + 1
  ; If result < 0, no more lines above
  BMI .jl_batch_apply

  ; Check that the line above is empty.
  ; An empty line is a \n preceded by another \n or at start of buffer.
  ; The \n of the line above is at BUF_PTR16 - X - 1.
  SEC
  LDA BUF_PTR16
  SBC BUF_TEMP
  STA BUF_SRC16
  LDA BUF_PTR16 + 1
  SBC #0
  STA BUF_SRC16 + 1
  ; Subtract 1 more to point to the \n
  SEC
  LDA BUF_SRC16
  SBC #1
  STA BUF_SRC16
  LDA BUF_SRC16 + 1
  SBC #0
  STA BUF_SRC16 + 1
  ; Verify it's a \n
  LDY #0
  LDA (BUF_SRC16),Y
  CMP #'\n'
  BNE .jl_batch_apply     ; Not a newline, stop
  ; Check if this \n is at TEXT_BUF (start of buffer = first line is empty)
  LDA BUF_SRC16
  CMP #<TEXT_BUF
  BNE .jl_check_prev_byte
  LDA BUF_SRC16 + 1
  CMP #>TEXT_BUF
  BEQ .jl_line_is_empty   ; At buffer start, line is empty
.jl_check_prev_byte:
  ; Check byte before this \n - must be \n for line to be empty
  SEC
  LDA BUF_SRC16
  SBC #1
  STA BUF_DST16
  LDA BUF_SRC16 + 1
  SBC #0
  STA BUF_DST16 + 1
  LDY #0
  LDA (BUF_DST16),Y
  CMP #'\n'
  BNE .jl_batch_apply     ; Previous byte is not \n, line has content
.jl_line_is_empty:

  ; Check if input is available
  STX BUF_TEMP
  JSR input_ready
  CMP #$FF
  BNE .jl_batch_restore_x ; No more input
  ; Read byte
  JSR input_read_byte
  ; Check if it's backspace ($08 or $7F)
  CMP #KEY_BS
  BEQ .jl_batch_match
  CMP #$7F
  BEQ .jl_batch_match
  ; Not backspace, push back and stop
  JSR input_unread
  LDX BUF_TEMP
  JMP .jl_batch_apply

.jl_batch_match:
  LDX BUF_TEMP
  INX
  CPX #BATCH_MAX
  BEQ .jl_batch_apply
  JMP .jl_batch_loop

.jl_batch_restore_x:
  LDX BUF_TEMP

.jl_batch_apply:
  ; X = number of additional newlines to delete
  CPX #0
  BEQ .jl_batch_done

  STX BUF_DELTA

  ; Point to first \n to delete: BUF_PTR16 - BUF_DELTA
  SEC
  LDA BUF_PTR16
  SBC BUF_DELTA
  STA BUF_PTR16
  LDA BUF_PTR16 + 1
  SBC #0
  STA BUF_PTR16 + 1

  ; Delete BUF_DELTA bytes
  JSR buf_delete_chars

  ; Subtract BUF_DELTA from FILE_LINE16
  SEC
  LDA FILE_LINE16
  SBC BUF_DELTA
  STA FILE_LINE16
  LDA FILE_LINE16 + 1
  SBC #0
  STA FILE_LINE16 + 1

  ; Rebuild line table once
  JSR buf_rebuild_lines

.jl_batch_done:
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
