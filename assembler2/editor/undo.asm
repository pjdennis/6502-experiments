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

UNDO_NONE = 0
UNDO_LINE = 1
UNDO_CHAR = 2
UNDO_CC   = 3
UNDO_JOIN = 4
UNDO_LINE_PASTE_BELOW = 5
UNDO_LINE_PASTE_ABOVE = 6
UNDO_CHAR_PASTE_BELOW = 7
UNDO_CHAR_PASTE_ABOVE = 8

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
  CMP #UNDO_JOIN
  BEQ .undo_join
  CMP #UNDO_CC
  BEQ .undo_cc
  CMP #UNDO_LINE
  BEQ .undo_line
  JMP .undo_char

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
.undo_char_flags:
  ; Restore cursor position (yank_paste_core may have moved things)
  CP16 UNDO_COL16, CURSOR_COL16
  ; Set flags
  LDA #$FF
  STA UNDO_IS_REDO
  STA MODIFIED
  LDA #1
  STA RENDER_FLAG
  JMP clear_count

.undo_fail:
  JMP clear_count

; --- Redo ---
undo_do_redo:
  LDA UNDO_TYPE
  CMP #UNDO_JOIN
  BEQ .redo_join
  CMP #UNDO_CC
  BEQ .redo_cc
  CMP #UNDO_LINE
  BEQ .redo_line
  JMP .redo_char

.redo_join:
  JMP undo_join_redo

.redo_cc:
  ; cc redo: delete lines, insert blank line (reproduces cc effect)
  CP16 UNDO_LINE16, FILE_LINE16
  CP16 YANK_LINES16, BUF_TEMP16
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
  LDA #$02
  STA RENDER_FLAG
  JMP clear_count

.redo_line:
  ; Restore FILE_LINE16
  CP16 UNDO_LINE16, FILE_LINE16
  ; Get yank size to know how many lines to delete
  CP16 YANK_LINES16, BUF_TEMP16
  JSR delete_current_lines
  ; Set flags
  LDA #0
  STA UNDO_IS_REDO
  LDA #$FF
  STA MODIFIED
  LDA #$02
  STA RENDER_FLAG            ; Signal line-delete for scroll optimization
  JSR clamp_cursor_col
  JMP clear_count

.redo_char:
  ; Restore position
  CP16 UNDO_LINE16, FILE_LINE16
  CP16 UNDO_COL16, CURSOR_COL16
  ; Get yank size for delete count
  JSR yank_get_size          ; BUF_LEN16 = yank size
  BCS .redo_fail
  JSR delete_at_cursor       ; Delete BUF_LEN16 bytes at cursor
  ; Restore cursor
  CP16 UNDO_COL16, CURSOR_COL16
  JSR clamp_cursor_col
  ; Set flags
  LDA #0
  STA UNDO_IS_REDO
  LDA #1
  STA RENDER_FLAG
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
  LDA #$02
  STA RENDER_FLAG
  JSR clamp_cursor_col
  JMP clear_count

