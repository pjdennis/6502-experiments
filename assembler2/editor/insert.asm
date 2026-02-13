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
  .byte KEY_ESC     .word insert_exit
  .byte KEY_ENTER   .word insert_newline
  .byte KEY_BS      .word insert_backspace
  .byte KEY_DEL     .word insert_delete
  .byte KEY_UP      .word insert_move_up
  .byte KEY_DOWN    .word insert_move_down
  .byte KEY_LEFT    .word insert_move_left
  .byte KEY_RIGHT   .word insert_move_right
  .byte KEY_HOME    .word insert_home
  .byte KEY_END     .word insert_end
  .byte KEY_PGDN    .word insert_page_down
  .byte KEY_PGUP    .word insert_page_up
  .byte $06         .word insert_page_down    ; Ctrl-F
  .byte $02         .word insert_page_up      ; Ctrl-B
  .byte KEY_WORD_FWD  .word insert_word_forward
  .byte KEY_WORD_BACK .word insert_word_backward
  .byte 0           ; End sentinel

; Exit insert mode, return to normal mode
insert_exit:
  LDA #MODE_NORMAL
  STA MODE
  ; Move cursor back one per vi convention (unless at column 0)
  TST16 CURSOR_COL16
  BEQ .done
  DEC16 CURSOR_COL16
.done:
  RTS

; Insert a printable character at cursor position
; Character in A. Reads and batches pending printable chars, Enter, and BS.
insert_char:
  ; Store first char in BATCH_BUF[0]
  STA BATCH_BUF
  LDX #1

  ; Read pending chars into BATCH_BUF[1..] (printable, Enter as \n, BS cancels)
.batch_read:
  JSR key_ready
  CMP #$FF
  BNE .batch_apply
  JSR get_key
  CMP #KEY_ENTER
  BEQ .batch_enter
  CMP #KEY_BS
  BEQ .batch_bs
  ; Check if printable ($20-$7E)
  CMP #' '
  BCC .batch_not_printable
  CMP #$7F
  BCS .batch_not_printable
.batch_store:
  STA BATCH_BUF,X
  INX
  CPX #BATCH_MAX
  BNE .batch_read
  JMP .batch_apply

.batch_enter:
  LDA #'\n'
  JMP .batch_store

.batch_bs:
  CPX #0
  BEQ .batch_bs_empty
  DEX                       ; Cancel last char/newline in batch
  JMP .batch_read
.batch_bs_empty:
  JSR unget_key             ; Push BS back for normal handler
  JMP .batch_apply          ; BUF_DELTA will be 0 -> no-op

.batch_not_printable:
  JSR unget_key

.batch_apply:
  STX BUF_DELTA
  CPX #0
  BEQ .batch_noop           ; BS canceled everything

  JSR get_cursor_buf_ptr
  JSR buf_insert_chars
  BCS .insert_char_full

  ; Scan BATCH_BUF for newlines
  LDA #0
  STA BUF_TEMP              ; Newline count
  TAY                       ; Y = scan index
.scan_nl:
  LDA BATCH_BUF,Y
  CMP #'\n'
  BNE .scan_not_nl
  INC BUF_TEMP
  TYA
  CLC
  ADC #1
  STA LINE_LEN16            ; Track position after last \n
.scan_not_nl:
  INY
  CPY BUF_DELTA
  BNE .scan_nl

  LDA BUF_TEMP
  BEQ .no_newlines

  ; --- Newline path: rebuild lines + adjust marks + advance line ---
  JSR buf_rebuild_lines

  ; mark_adjust_insert: BUF_TEMP16 lines at FILE_LINE16+1
  LDA BUF_TEMP
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16 + 1
  CLC
  ADCI16 FILE_LINE16, $0001, BUF_DST16
  LDAX16 BUF_DST16
  JSR mark_adjust_insert

  ; Advance FILE_LINE16 by newline count
  LDA BUF_TEMP
  CLC
  ADCA16 FILE_LINE16, FILE_LINE16

  ; CURSOR_COL16 = BUF_DELTA - LINE_LEN16 (bytes after last \n)
  SEC
  LDA BUF_DELTA
  SBC LINE_LEN16
  STA CURSOR_COL16
  LDA #0
  STA CURSOR_COL16 + 1

  LDA #$FF
  STA MODIFIED
  RTS

.no_newlines:
  ; --- Fast path: no newlines (existing behavior) ---
  JSR buf_adjust_lines_inc

  ; Advance cursor by BUF_DELTA
  LDA BUF_DELTA
  CLC
  ADCA16 CURSOR_COL16, CURSOR_COL16

  LDA #$FF
  STA MODIFIED
  RTS

.batch_noop:
  RTS

.insert_char_full:
  JMP show_buffer_full_msg

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
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16 + 1
  CLC
  ADCI16 FILE_LINE16, $0001, BUF_DST16
  LDAX16 BUF_DST16
  JSR mark_adjust_insert

  ; Advance FILE_LINE16 by BUF_DELTA
  LDA BUF_DELTA
  CLC
  ADCA16 FILE_LINE16, FILE_LINE16

  LDA #0
  STA_LH16 CURSOR_COL16
  LDA #$FF
  STA MODIFIED
  RTS
.insert_newline_full:
  JMP show_buffer_full_msg

; Handle backspace in insert mode
insert_backspace:
  ; If at column 0, join with previous line
  TST16 CURSOR_COL16
  BEQ .join_lines

  ; Count pending BS keys inline, capped at CURSOR_COL16 (max 255)
  ; Start with 1 for the current BS key
  LDX #1
.count_loop:
  ; Cap at 255 or CURSOR_COL16 (whichever is smaller)
  LDA CURSOR_COL16 + 1
  BNE .count_no_cap        ; High byte > 0, X < CURSOR_COL16 for sure
  CPX CURSOR_COL16
  BEQ .count_done           ; At cap, stop
.count_no_cap:
  JSR key_ready
  CMP #$FF
  BNE .count_done
  JSR get_key
  CMP #KEY_BS
  BEQ .count_match
  ; Not backspace, push back and stop
  JSR unget_key
  JMP .count_done
.count_match:
  INX
  CPX #BATCH_MAX
  BNE .count_loop
.count_done:

  STX BUF_DELTA
  ; Update cursor: CURSOR_COL16 -= BUF_DELTA
  SEC
  LDA CURSOR_COL16
  SBC BUF_DELTA
  STA CURSOR_COL16
  LDA CURSOR_COL16 + 1
  SBC #0
  STA CURSOR_COL16 + 1
  ; Get buffer pointer at new cursor position
  JSR get_cursor_buf_ptr
  ; Delete BUF_DELTA chars
  JSR buf_delete_chars
  JSR buf_adjust_lines_dec

  LDA #$FF
  STA MODIFIED
  RTS

.join_lines:
  ; At column 0 - join with previous line
  TST16 FILE_LINE16
  BNE .can_join
  RTS                      ; Can't join at first line
.can_join:
  ; Get previous line length -> CURSOR_COL16
  SEC
  SBCI16 FILE_LINE16, $0001, BUF_LEN16
  LDAX16 BUF_LEN16
  JSR buf_get_line_len
  STAX16 CURSOR_COL16

  ; Point BUF_PTR16 to the newline ending the previous line
  LDAX16 BUF_LEN16
  JSR buf_get_line_ptr
  CLC
  ADC16 CURSOR_COL16, BUF_PTR16, BUF_PTR16

  ; X = count of newlines to delete (starts at 1 for the first join)
  LDX #1

  ; If previous line has content, skip batch scan
  TST16 CURSOR_COL16
  BNE .apply

  ; Previous line empty - scan backwards for consecutive \n bytes
.scan_loop:
  ; Check if BUF_PTR16 is at TEXT_BUF (buffer start)
  CMPI16 BUF_PTR16, TEXT_BUF
  BEQ .apply           ; At buffer start, stop

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
  CMPI16 BUF_SRC16, TEXT_BUF
  BEQ .line_empty      ; First byte of buffer, just \n -> empty

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
  BNE .apply           ; Byte before is not \n -> content line -> stop

.line_empty:

  ; Read one BS key from input
  STX BUF_TEMP
  JSR key_ready
  CMP #$FF
  BNE .restore_x
  JSR get_key
  CMP #KEY_BS
  BEQ .match
  ; Not backspace, push back and stop
  JSR unget_key
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
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16 + 1
  CLC
  ADCI16 FILE_LINE16, $0001, BUF_DST16
  LDAX16 BUF_DST16
  JSR mark_adjust_delete

  LDA #$FF
  STA MODIFIED
  RTS

; Handle delete in insert mode (forward delete)
; Unified algorithm: counts all pending DEL keys, scans forward through
; the buffer consuming chars and newlines, deletes everything in one call.
insert_delete:
  ; Count all pending DEL keys (BUF_TEMP = KEY_DEL from dispatch)
  JSR count_pending_key       ; X = pending count
  INX                         ; +1 for current
  STX BUF_TEMP                ; total DEL count

  ; Get cursor buffer position
  JSR get_cursor_buf_ptr      ; BUF_PTR16 = cursor

  ; Pre-compute address of final \n (BUF_END16 - 1)
  SEC
  LDA BUF_END16
  SBC #1
  STA LINE_LEN16
  LDA BUF_END16 + 1
  SBC #0
  STA LINE_LEN16 + 1

  ; Initialize scan state
  LDA #0
  STA BUF_DELTA               ; bytes to delete
  STA_LH16 BUF_TEMP16         ; newline count = 0
  CP16 BUF_PTR16, BUF_SRC16   ; scan ptr = cursor

.scan:
  LDA BUF_TEMP
  BEQ .scan_done              ; no more DELs

  CMP16 BUF_SRC16, BUF_END16
  BCS .scan_done              ; at/past buffer end

  LDY #0
  LDA (BUF_SRC16),Y
  CMP #'\n'
  BNE .scan_advance

  ; It's a \n - is it the final one?
  CMP16 BUF_SRC16, LINE_LEN16
  BCS .scan_done              ; final \n, stop

  INC BUF_TEMP16              ; count deleted newline

.scan_advance:
  INC16 BUF_SRC16
  INC BUF_DELTA
  DEC BUF_TEMP
  JMP .scan

.scan_done:
  ; Anything to delete?
  LDA BUF_DELTA
  BEQ .done                   ; no-op (DEL at end of last line)

  ; Delete BUF_DELTA bytes at BUF_PTR16
  JSR buf_delete_chars

  ; Rebuild or fast path
  LDA BUF_TEMP16
  ORA BUF_TEMP16 + 1
  BEQ .no_newlines

  ; Newlines deleted: full rebuild + mark adjust
  JSR buf_rebuild_lines
  CLC
  ADCI16 FILE_LINE16, $0001, BUF_DST16
  LDAX16 BUF_DST16
  JSR mark_adjust_delete
  JMP .set_modified

.no_newlines:
  JSR buf_adjust_lines_dec    ; fast path, no line count change

.set_modified:
  LDA #$FF
  STA MODIFIED

.done:
  RTS

; Arrow key handlers in insert mode
; These implement simple line movement without the normal mode clamping
; that would clamp to len-1 instead of len (one past last char for insert)

insert_move_up:
  ; Batch pending UP keys and move up
  LDA #KEY_UP
  STA BUF_TEMP
  JSR count_pending_key  ; X = pending matching keys
  INX                     ; +1 for current key
  JSR move_up_x
  JSR clamp_cursor_col_insert
  RTS

insert_move_down:
  ; Batch pending DOWN keys and move down
  LDA #KEY_DOWN
  STA BUF_TEMP
  JSR count_pending_key  ; X = pending matching keys
  INX                     ; +1 for current key
  JSR move_down_x
  JSR clamp_cursor_col_insert
  RTS

insert_page_down:
  JSR normal_page_down
  JMP clamp_cursor_col_insert

insert_page_up:
  JSR normal_page_up
  JMP clamp_cursor_col_insert

insert_move_left:
  LDA #KEY_LEFT
  STA BUF_TEMP
  JSR count_pending_key  ; X = pending matching keys
  INX                     ; +1 for current key
  JSR move_left_x
  RTS

insert_move_right:
  LDA #KEY_RIGHT
  STA BUF_TEMP
  JSR count_pending_key  ; X = pending matching keys
  INX                     ; +1 for current key
  ; Hoist line length calculation (line doesn't change)
  STX BUF_DELTA          ; Save count
  JSR get_current_line_len
  STAX16 LINE_LEN16
  LDX BUF_DELTA          ; Restore count
  JSR move_right_x
  RTS

insert_home:
  TST16 CURSOR_COL16
  BEQ .done            ; Already at column 0
  LDA #0
  STA_LH16 CURSOR_COL16
.done:
  RTS

insert_end:
  JSR get_current_line_len
  STAX16 LINE_LEN16
  CMP16 LINE_LEN16, CURSOR_COL16
  BEQ .done            ; Already at end
  BCC .done
  CP16 LINE_LEN16, CURSOR_COL16
.done:
  RTS

insert_word_forward:
  LDA #KEY_WORD_FWD
  STA BUF_TEMP
  JSR count_pending_key   ; X = pending matching keys
  INX                     ; +1 for current key
  JSR word_forward_x
  JSR clamp_cursor_col_insert
  RTS

insert_word_backward:
  LDA #KEY_WORD_BACK
  STA BUF_TEMP
  JSR count_pending_key   ; X = pending matching keys
  INX                     ; +1 for current key
  JSR word_backward_x
  JSR clamp_cursor_col_insert
  RTS

; Clamp cursor for insert mode (can be one past end of line content)
clamp_cursor_col_insert:
  JSR get_current_line_len
  STAX16 LINE_LEN16
  CMP16 LINE_LEN16, CURSOR_COL16
  BCS .ok
  CP16 LINE_LEN16, CURSOR_COL16
.ok:
  RTS
