; Undo/redo support for normal mode deletion commands
;
; Single-level undo: 'u' toggles between undo and redo.
; The yank buffer stores deleted content, so undo = paste it back,
; redo = re-delete it.
;
; UNDO_TYPE values:
;   0 = none (no undoable operation)
;   1 = line-delete (dd, 2dd, etc.)
;   2 = char-delete (x, D, dw, db, de)
;   3 = cc/S line-delete (like line-delete but cc inserted blank line)
;   4 = join (J, NJ)
;   5 = line-paste-below (p with line yank)
;   6 = line-paste-above (P with line yank)
;   7 = char-paste-below (p with char yank)
;   8 = char-paste-above (P with char yank)
;   9 = open-line (o/O opened blank line(s))

UNDO_NONE = 0
UNDO_LINE = 1
UNDO_CHAR = 2
UNDO_CC   = 3
UNDO_JOIN = 4
UNDO_LINE_PASTE_BELOW = 5
UNDO_LINE_PASTE_ABOVE = 6
UNDO_CHAR_PASTE_BELOW = 7
UNDO_CHAR_PASTE_ABOVE = 8
UNDO_OPEN = 9

JOIN_UNDO_BUF = $D700     ; 256 bytes for 16-bit offsets
JOIN_UNDO_MAX = 128       ; 256 / 2 bytes per entry

  .zeropage

UNDO_TYPE:       .byte    ; 0=none, 1-4=delete/cc/join, 5-8=paste
UNDO_LINE16:     .word    ; FILE_LINE16 at time of operation
UNDO_COL16:      .word    ; CURSOR_COL16 at time of operation
UNDO_IS_REDO:    .byte    ; 0=undo pending, $FF=redo pending
INSERT_CHANGED:  .byte    ; tracks if insert mode modified buffer
UNDO_JOIN_COUNT: .byte    ; Number of joins recorded (1-128)
UNDO_PASTE_COUNT16: .word ; Paste multiplier N (for redo), 16-bit

  .code

; Initialize undo state (call once at startup)
undo_init:
; Clear undo state (called when a new edit supersedes the undo slot)
undo_clear:
  LDA #UNDO_NONE
  STA UNDO_TYPE
  LDA #0
  STA UNDO_IS_REDO
  RTS

; Record a line-delete for undo
; Call after yank succeeds, before delete.
; Saves: type=1, FILE_LINE16
undo_record_line_delete:
  LDA #UNDO_LINE
  STA UNDO_TYPE
  CP16 FILE_LINE16, UNDO_LINE16
  LDA #0
  STA UNDO_IS_REDO
  RTS

; Record a cc/S line-delete for undo
; Like undo_record_line_delete but type=3 (cc inserted blank line to remove)
undo_record_cc:
  LDA #UNDO_CC
  STA UNDO_TYPE
  LDA #0
  STA UNDO_IS_REDO
  RTS

; Record a char-delete for undo
; Call at entry of yank_delete_at_cursor (before anything modified).
; Saves: type=2, FILE_LINE16, CURSOR_COL16
undo_record_char_delete:
  LDA #UNDO_CHAR
  STA UNDO_TYPE
  CP16 FILE_LINE16, UNDO_LINE16
  CP16 CURSOR_COL16, UNDO_COL16
  LDA #0
  STA UNDO_IS_REDO
  RTS

; Handle 'u' key: dispatch undo or redo based on UNDO_IS_REDO
; Batching: consume pending 'u' keys. Since u toggles undo/redo,
; odd total = one operation, even total = noop.
undo_handle:
  LDA UNDO_TYPE
  BEQ .done                  ; No undoable operation, no-op
  JSR count_pending_key      ; X = extra u keys in typeahead
  TXA
  AND #$01
  BNE .done                  ; Odd extras = even total = noop
  LDA UNDO_IS_REDO
  BNE .do_redo
  JMP undo_do_undo
.do_redo:
  JMP undo_do_redo
.done:
  JMP clear_count

; --- Undo ---
undo_do_undo:
  LDA UNDO_TYPE
  CMP #UNDO_OPEN
  BEQ .undo_open
  CMP #UNDO_LINE_PASTE_BELOW
  BCS .undo_paste
  CMP #UNDO_JOIN
  BEQ .undo_join
  CMP #UNDO_CC
  BEQ .undo_cc
  CMP #UNDO_LINE
  BEQ .undo_line
  JMP .undo_char

.undo_open:
  JMP undo_open_undo
.undo_paste:
  JMP undo_paste_undo
.undo_join:
  JMP undo_join_undo

.undo_cc:
  ; cc undo: first delete the blank line cc inserted, then paste original lines
  CP16 UNDO_LINE16, FILE_LINE16
  LDA #1
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16 + 1
  ; Check if current line is empty (should be if cc + ESC without typing)
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BNE .undo_cc_has_content
  ; Delete the blank line (with mark adjustment)
  JSR delete_current_lines
  JMP .undo_line_paste
.undo_cc_has_content:
  ; Line has content (shouldn't happen if insert exited clean, but be safe)
  JMP .undo_line_paste

.undo_line:
  ; Restore FILE_LINE16 to saved position
  CP16 UNDO_LINE16, FILE_LINE16

.undo_line_paste:
  ; Paste above: reuses existing yank_paste_above_n
  LDA #1
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16 + 1
  JSR yank_paste_above_n
  BCC .undo_line_ok
  JMP .undo_fail
.undo_line_ok:
  ; Adjust marks for inserted lines
  CP16 YANK_LINES16, BUF_TEMP16
  LDAX16 FILE_LINE16
  JSR mark_adjust_insert
  ; Set flags
  LDA #$FF
  STA UNDO_IS_REDO
  STA MODIFIED
  LDA YANK_LINES16           ; Actual lines inserted (may differ from net delta)
  STA INSERT_LINE_COUNT
  LDA UNDO_TYPE
  CMP #UNDO_CC
  BNE .undo_line_scroll
  ; cc undo: 1cc has net 0 line change (repaint cursor row only).
  ; Ncc (N>1): displacement may differ from file delta if lines wrap,
  ; so use full repaint for correctness.
  LDA YANK_LINES16
  CMP #2
  BCS .undo_cc_multi
  LDA #$01
  STA RENDER_FLAG            ; Single line repaint
  JMP clear_count
.undo_cc_multi:
  ; Ncc undo: compute SCROLL_DELTA = total_screen_rows(pasted) - 1
  ; (subtract 1 for the deleted blank line)
  CP16 FILE_LINE16, RENDER_LINE16
  LDA YANK_LINES16
  JSR compute_delete_screen_rows  ; Walks YANK_LINES16 lines, sets DELETE_SCREEN_ROWS
  LDA DELETE_SCREEN_ROWS
  BEQ .undo_cc_full              ; Overflow or 0: fall back to full repaint
  SEC
  SBC #1                         ; Subtract 1 for deleted blank line
  BEQ .undo_cc_full              ; 0 displacement: fall back
  STA SCROLL_DELTA
  LDA #0
  STA DELETE_SCREEN_ROWS         ; Reset (not needed for insert-scroll)
  LDA #$0A
  STA RENDER_FLAG                ; Pre-computed insert-scroll
  JMP clear_count
.undo_cc_full:
  LDA #0
  STA DELETE_SCREEN_ROWS
  LDA #$FF
  STA RENDER_FLAG                ; Fall back to full repaint
  JMP clear_count
.undo_line_scroll:
  LDA #$03
  STA RENDER_FLAG            ; Signal line-insert for scroll optimization
  JMP clear_count

.undo_char:
  ; Restore position
  CP16 UNDO_LINE16, FILE_LINE16
  CP16 UNDO_COL16, CURSOR_COL16
  ; Set up paste: BUF_TEMP16 = 1
  LDA #1
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16 + 1
  CP16 LINE_COUNT16, COUNT16 ; Save line count for mark adjustment
  JSR yank_paste_setup       ; BUF_LEN16 = yank size
  BCS .undo_fail
  JSR get_cursor_buf_ptr     ; BUF_PTR16 = cursor position
  JSR yank_paste_core        ; Shift right, copy yank data, rebuild
  BCS .undo_fail
  ; Adjust marks if paste added lines
  SEC
  SBC16 LINE_COUNT16, COUNT16, BUF_TEMP16
  TST16 BUF_TEMP16
  BEQ .undo_char_flags
  LDAX16 FILE_LINE16
  CLC
  JSR mark_adjust_col
  ; Multi-line: set scroll optimization, skip cursor row in scroll region
  LDAX16 FILE_LINE16
  JSR buf_get_line_len
  JSR line_screen_rows
  STA PREV_LINE_ROWS
  LDA #$09
  STA RENDER_FLAG
  ; INSERT_LINE_COUNT = new_lines + 1 (for split cursor line)
  LDA BUF_TEMP16
  CLC
  ADC #1
  STA INSERT_LINE_COUNT
  JMP .undo_char_set_flags
.undo_char_flags:
  LDA #1
  STA RENDER_FLAG
.undo_char_set_flags:
  ; Restore cursor position (yank_paste_core may have moved things)
  CP16 UNDO_COL16, CURSOR_COL16
  ; Set flags
  LDA #$FF
  STA UNDO_IS_REDO
  STA MODIFIED
  JMP clear_count

.undo_fail:
  JMP clear_count

; --- Redo ---
undo_do_redo:
  LDA UNDO_TYPE
  CMP #UNDO_OPEN
  BEQ .redo_open
  CMP #UNDO_LINE_PASTE_BELOW
  BCS .redo_paste
  CMP #UNDO_JOIN
  BEQ .redo_join
  CMP #UNDO_CC
  BEQ .redo_cc
  CMP #UNDO_LINE
  BEQ .redo_line
  JMP .redo_char

.redo_open:
  JMP undo_open_redo
.redo_paste:
  JMP undo_paste_redo
.redo_join:
  JMP undo_join_redo

.redo_cc:
  ; cc redo: delete lines, insert blank line (reproduces cc effect)
  CP16 UNDO_LINE16, FILE_LINE16
  CP16 YANK_LINES16, BUF_TEMP16
  ; Pre-compute screen rows for displacement-based scroll
  CP16 FILE_LINE16, RENDER_LINE16
  LDA BUF_TEMP16
  JSR compute_delete_screen_rows
  JSR delete_current_lines
  ; Insert blank line at FILE_LINE16 (like cc does)
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .redo_cc_done
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr
  LDA #'\n'
  JSR buf_insert_char
  BCS .redo_cc_done
  JSR buf_rebuild_lines
  ; Adjust marks for inserted blank line (matches original cc behavior)
  LDAX16 FILE_LINE16
  JSR mark_insert_one
.redo_cc_done:
  LDA #0
  STA UNDO_IS_REDO
  STA_LH16 CURSOR_COL16
  LDA #$FF
  STA MODIFIED
  LDA #$06
  STA RENDER_FLAG        ; displacement-based scroll
  JMP clear_count

.redo_line:
  ; Restore FILE_LINE16
  CP16 UNDO_LINE16, FILE_LINE16
  ; Get yank size to know how many lines to delete
  CP16 YANK_LINES16, BUF_TEMP16
  ; Pre-compute screen rows for line-delete scroll
  LDA BUF_TEMP16 + 1
  BNE .redo_line_skip_pre
  CP16 FILE_LINE16, RENDER_LINE16
  LDA BUF_TEMP16
  JSR compute_delete_screen_rows
  JMP .redo_line_del
.redo_line_skip_pre:
  LDA #0
  STA DELETE_SCREEN_ROWS
.redo_line_del:
  JSR delete_current_lines
  ; Save pre-computed screen rows as SCROLL_DELTA before clearing
  ; (accounts for wrapped lines: file delta = 1 line, but screen delta = 2+ rows)
  LDA DELETE_SCREEN_ROWS
  STA SCROLL_DELTA
  ; Set flags
  LDA #0
  STA UNDO_IS_REDO
  STA DELETE_SCREEN_ROWS     ; Scroll starts at cursor row (cursor filled by scroll)
  LDA #$FF
  STA MODIFIED
  LDA #$07
  STA RENDER_FLAG            ; Line-delete scroll, skip cursor repaint
  JSR clamp_cursor_col
  JMP clear_count

.redo_char:
  ; Restore position
  CP16 UNDO_LINE16, FILE_LINE16
  CP16 UNDO_COL16, CURSOR_COL16
  ; Get yank size for delete count
  JSR yank_get_size          ; BUF_LEN16 = yank size
  BCS .redo_fail
  JSR delete_at_cursor       ; Delete BUF_LEN16 bytes at cursor (sets RENDER_FLAG=$02 if multi-line)
  ; Restore cursor
  CP16 UNDO_COL16, CURSOR_COL16
  JSR clamp_cursor_col
  ; Set flags (keep RENDER_FLAG from delete_at_cursor if > 1)
  LDA #0
  STA UNDO_IS_REDO
  LDA RENDER_FLAG
  CMP #2
  BCS .redo_char_done
  LDA #1
  STA RENDER_FLAG
.redo_char_done:
  JMP clear_count

.redo_fail:
  JMP clear_count

; --- Join undo: replace spaces back to newlines ---
undo_join_undo:
  CP16 UNDO_LINE16, FILE_LINE16
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr          ; BUF_PTR16 = line start
  CP16 BUF_PTR16, BUF_SRC16    ; BUF_SRC16 = line start (base for offsets)

  LDX #0                       ; X = buffer index
  LDA UNDO_JOIN_COUNT
  STA NORMAL_TEMP               ; loop counter
.undo_join_loop:
  LDA JOIN_UNDO_BUF,X
  STA BUF_PTR16
  INX
  LDA JOIN_UNDO_BUF,X
  STA BUF_PTR16 + 1
  INX
  ; BUF_PTR16 = offset; compute address = BUF_SRC16 + offset
  CLC
  ADC16 BUF_SRC16, BUF_PTR16, BUF_PTR16
  LDY #0
  LDA #'\n'
  STA (BUF_PTR16),Y
  DEC NORMAL_TEMP
  BNE .undo_join_loop

  JSR buf_rebuild_lines

  ; Adjust marks: insert UNDO_JOIN_COUNT lines after FILE_LINE16
  LDA UNDO_JOIN_COUNT
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16 + 1
  CLC
  ADCI16 FILE_LINE16, 1, BUF_PTR16
  LDAX16 BUF_PTR16
  JSR mark_adjust_insert

  ; Set flags
  LDA #$FF
  STA UNDO_IS_REDO
  STA MODIFIED
  ; Repaint cursor line + restored lines (cursor line content also changed)
  LDA UNDO_JOIN_COUNT
  CLC
  ADC #1
  STA INSERT_LINE_COUNT
  LDA #$04
  STA RENDER_FLAG            ; Line-insert scroll, skip cursor row
  JSR clamp_cursor_col
  JMP clear_count

; --- Join redo: replace newlines back to spaces ---
undo_join_redo:
  CP16 UNDO_LINE16, FILE_LINE16

  ; Pre-compute old_total screen rows for displacement-based scroll
  CP16 FILE_LINE16, RENDER_LINE16
  LDA UNDO_JOIN_COUNT
  CLC
  ADC #1           ; +1 for cursor line
  JSR compute_delete_screen_rows

  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr          ; BUF_PTR16 = line start
  CP16 BUF_PTR16, BUF_SRC16    ; BUF_SRC16 = line start (base for offsets)

  LDX #0                       ; X = buffer index
  LDA UNDO_JOIN_COUNT
  STA NORMAL_TEMP               ; loop counter
.redo_join_loop:
  LDA JOIN_UNDO_BUF,X
  STA BUF_PTR16
  INX
  LDA JOIN_UNDO_BUF,X
  STA BUF_PTR16 + 1
  INX
  ; Compute address = BUF_SRC16 + offset
  CLC
  ADC16 BUF_SRC16, BUF_PTR16, BUF_PTR16
  LDY #0
  LDA #' '
  STA (BUF_PTR16),Y
  DEC NORMAL_TEMP
  BNE .redo_join_loop

  JSR buf_rebuild_lines

  ; Adjust marks: delete UNDO_JOIN_COUNT lines after FILE_LINE16
  LDA UNDO_JOIN_COUNT
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16 + 1
  CLC
  ADCI16 FILE_LINE16, 1, BUF_PTR16
  LDAX16 BUF_PTR16
  JSR mark_adjust_delete

  ; Set flags
  LDA #0
  STA UNDO_IS_REDO
  LDA #$FF
  STA MODIFIED
  LDA #$06
  STA RENDER_FLAG        ; Line-delete, skip cursor row scroll
  JSR clamp_cursor_col
  JMP clear_count

; --- Paste undo ---
undo_paste_undo:
  LDA UNDO_TYPE
  CMP #UNDO_CHAR_PASTE_BELOW
  BCS .undo_char_paste
  ; Line paste undo: set FILE_LINE16 to first pasted line
  CP16 UNDO_LINE16, FILE_LINE16
  LDA UNDO_TYPE
  CMP #UNDO_LINE_PASTE_BELOW
  BNE .undo_line_paste
  INC16 FILE_LINE16            ; BELOW: pasted lines start one past saved

.undo_line_paste:
  ; BUF_TEMP16 = YANK_LINES16 * UNDO_PASTE_COUNT16
  JSR undo_compute_paste_lines
  JSR delete_current_lines
  ; Restore cursor
  CP16 UNDO_LINE16, FILE_LINE16
  CP16 UNDO_COL16, CURSOR_COL16
  JSR clamp_cursor_col
  ; Set flags
  LDA #$FF
  STA UNDO_IS_REDO
  STA MODIFIED
  ; Paste-below undo: cursor row unchanged, skip it in scroll region ($07)
  ; Paste-above undo: cursor row changes, include it ($02)
  LDA UNDO_TYPE
  CMP #UNDO_LINE_PASTE_BELOW
  BNE .undo_paste_above_flag
  ; Pre-compute cursor line screen rows for skip-scroll
  LDAX16 UNDO_LINE16
  JSR buf_get_line_len
  JSR line_screen_rows
  STA DELETE_SCREEN_ROWS
  LDA #$07
  STA RENDER_FLAG
  JMP clear_count
.undo_paste_above_flag:
  ; Cursor row filled by scroll (original line pulled up), skip repaint
  LDA #0
  STA DELETE_SCREEN_ROWS
  LDA #$07
  STA RENDER_FLAG
  JMP clear_count

.undo_char_paste:
  JMP undo_char_paste_undo

; --- Paste redo ---
undo_paste_redo:
  LDA UNDO_TYPE
  CMP #UNDO_CHAR_PASTE_BELOW
  BCS .redo_char_paste
  ; Line paste redo: common setup
  CP16 UNDO_LINE16, FILE_LINE16
  CP16 UNDO_PASTE_COUNT16, BUF_TEMP16
  LDA UNDO_TYPE
  CMP #UNDO_LINE_PASTE_ABOVE
  BEQ .redo_line_paste_above
  JSR yank_paste_below_n
  JMP .redo_line_paste_done
.redo_line_paste_above:
  JSR yank_paste_above_n
.redo_line_paste_done:
  BCS .redo_fail
  ; paste_adjust_marks needs BUF_TEMP16 = count
  CP16 UNDO_PASTE_COUNT16, BUF_TEMP16
  JSR paste_adjust_marks
  ; Set flags
  LDA #0
  STA UNDO_IS_REDO
  LDA #$FF
  STA MODIFIED
  ; INSERT_LINE_COUNT = total pasted lines (in BUF_TEMP16 from paste_adjust_marks)
  LDA BUF_TEMP16
  STA INSERT_LINE_COUNT
  LDA #$03
  STA RENDER_FLAG
  JMP clear_count

.redo_fail:
  JMP clear_count

.redo_char_paste:
  JMP undo_char_paste_redo

; Compute BUF_TEMP16 = YANK_LINES16 * UNDO_PASTE_COUNT16 (16-bit)
; Clobbers: A, COUNT16
undo_compute_paste_lines:
  CP16 YANK_LINES16, BUF_TEMP16
  CMPI16 UNDO_PASTE_COUNT16, 1
  BEQ .done
  CP16 UNDO_PASTE_COUNT16, COUNT16
  DEC16 COUNT16
.mul:
  CLC
  ADC16 BUF_TEMP16, YANK_LINES16, BUF_TEMP16
  DEC16 COUNT16
  TST16 COUNT16
  BNE .mul
.done:
  RTS

; --- Char paste undo (handles both BELOW and ABOVE) ---
undo_char_paste_undo:
  ; Position at insertion point and delete pasted content
  CP16 UNDO_LINE16, FILE_LINE16
  CP16 UNDO_COL16, CURSOR_COL16
  CP16 UNDO_PASTE_COUNT16, BUF_TEMP16
  JSR yank_paste_setup         ; BUF_LEN16 = total paste size
  BCS .undo_cp_fail
  JSR delete_at_cursor         ; Deletes BUF_LEN16 bytes, handles marks
  ; Restore cursor
  CP16 UNDO_LINE16, FILE_LINE16
  LDA UNDO_TYPE
  CMP #UNDO_CHAR_PASTE_ABOVE
  BEQ .undo_cp_above
  ; BELOW: pre-paste col = max(insertion_col - 1, 0)
  TST16 UNDO_COL16
  BEQ .undo_cp_col_zero
  SEC
  SBCI16 UNDO_COL16, 1, CURSOR_COL16
  JMP .undo_cp_flags
.undo_cp_above:
  CP16 UNDO_COL16, CURSOR_COL16
  JMP .undo_cp_flags
.undo_cp_col_zero:
  LDA #0
  STA_LH16 CURSOR_COL16
.undo_cp_flags:
  JSR clamp_cursor_col
  LDA #$FF
  STA UNDO_IS_REDO
  STA MODIFIED
  ; Keep RENDER_FLAG from delete_at_cursor if > 1 (multi-line scroll)
  LDA RENDER_FLAG
  CMP #2
  BCS .undo_cp_done
  LDA #1
  STA RENDER_FLAG
.undo_cp_done:
  JMP clear_count
.undo_cp_fail:
  JMP clear_count

; --- Char paste redo (handles both BELOW and ABOVE) ---
undo_char_paste_redo:
  CP16 UNDO_LINE16, FILE_LINE16
  LDA #0
  STA BATCH_EXTRA
  CP16 UNDO_PASTE_COUNT16, BUF_TEMP16
  LDA UNDO_TYPE
  CMP #UNDO_CHAR_PASTE_ABOVE
  BEQ .redo_cpa
  ; BELOW: cursor = max(insertion_col - 1, 0)
  TST16 UNDO_COL16
  BEQ .redo_cp_col_zero
  SEC
  SBCI16 UNDO_COL16, 1, CURSOR_COL16
  JMP .redo_cpb_paste
.redo_cp_col_zero:
  LDA #0
  STA_LH16 CURSOR_COL16
.redo_cpb_paste:
  JSR do_char_paste_below
  JMP .redo_cp_flags
.redo_cpa:
  CP16 UNDO_COL16, CURSOR_COL16
  JSR do_char_paste_above
.redo_cp_flags:
  LDA #0
  STA UNDO_IS_REDO
  ; Keep RENDER_FLAG from do_char_paste if > 1 (multi-line scroll)
  LDA RENDER_FLAG
  CMP #2
  BCS .redo_cp_done
  LDA #1
  STA RENDER_FLAG
.redo_cp_done:
  JMP clear_count

; --- Open-line undo: delete the opened blank line(s) ---
undo_open_undo:
  ; Delete the opened line
  CP16 UNDO_LINE16, FILE_LINE16
  SET16 1, BUF_TEMP16
  LDA #0
  STA DELETE_SCREEN_ROWS     ; Cursor row filled by scroll
  JSR delete_current_lines
  ; Restore cursor to original position
  CP16 UNDO_COL16, FILE_LINE16
  LDA #0
  STA_LH16 CURSOR_COL16
  JSR clamp_cursor_col
  ; Set flags
  LDA #$FF
  STA UNDO_IS_REDO
  STA MODIFIED
  LDA #$07
  STA RENDER_FLAG            ; Delete scroll, skip cursor repaint
  JMP clear_count

; --- Open-line redo: re-insert blank line ---
undo_open_redo:
  ; Insert blank line at UNDO_LINE16
  LDAX16 UNDO_LINE16
  JSR buf_get_line_ptr
  LDA #'\n'
  JSR buf_insert_char
  BCS .redo_open_fail
  JSR buf_rebuild_lines
  ; Adjust marks
  LDAX16 UNDO_LINE16
  JSR mark_insert_one
  ; Set cursor on opened line
  CP16 UNDO_LINE16, FILE_LINE16
  LDA #0
  STA UNDO_IS_REDO
  STA_LH16 CURSOR_COL16
  LDA #$FF
  STA MODIFIED
  LDA #$03
  STA RENDER_FLAG            ; Insert scroll
  JMP clear_count
.redo_open_fail:
  JMP clear_count

