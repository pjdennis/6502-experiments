; Normal mode editing commands - paste, toggle case, join, substitute,
; change line, indent/unindent, word delete/change

; --- Paste ---

normal_paste_below:
  LDA YANK_TYPE
  BEQ .line_paste
  JMP char_paste_below
.line_paste:
  JSR get_count              ; BUF_TEMP16 = count
  LDX BUF_TEMP16             ; X = count (low byte)
  STX NORMAL_TEMP            ; Save paste count
  JSR yank_paste_below_n
  BCS .paste_below_done
  JSR paste_adjust_marks
.paste_below_done:
  JMP clear_count

normal_paste_above:
  LDA YANK_TYPE
  BEQ .line_paste
  JMP char_paste_above
.line_paste:
  JSR get_count              ; BUF_TEMP16 = count
  LDX BUF_TEMP16             ; X = count (low byte)
  STX NORMAL_TEMP            ; Save paste count
  JSR yank_paste_above_n
  BCS .paste_above_done
  JSR paste_adjust_marks
.paste_above_done:
  JMP clear_count

; Character paste below (after cursor)
; For non-empty lines, inserts after cursor char; for empty lines, inserts at line start
char_paste_below:
  JSR get_count              ; BUF_TEMP16 = count
  JSR yank_paste_setup
  BCS .done                  ; Empty yank

  ; Save total paste size on stack
  PUSH16 BUF_LEN16

  ; Compute insertion point
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .empty_line

  ; Non-empty line: insert after cursor
  JSR get_cursor_buf_ptr
  INC16 BUF_PTR16
  LDA #1                     ; Flag: non-empty line
  PHA
  JMP .do_paste

.empty_line:
  JSR get_cursor_buf_ptr     ; Insert at line start
  LDA #0                     ; Flag: empty line
  PHA

.do_paste:
  JSR yank_paste_core
  PLA                        ; Recover empty-line flag
  STA NORMAL_TEMP            ; Save temporarily
  POP16 BUF_LEN16            ; Recover total paste size
  BCS .done                  ; Paste failed (buffer full)

  ; Adjust cursor column
  LDA NORMAL_TEMP
  BEQ .cursor_empty

  ; Non-empty: CURSOR_COL16 += BUF_LEN16
  CLC
  ADC16 CURSOR_COL16, BUF_LEN16, CURSOR_COL16
  JMP .cursor_done

.cursor_empty:
  ; Empty line: CURSOR_COL16 = BUF_LEN16 - 1
  SEC
  SBCI16 BUF_LEN16, 1, CURSOR_COL16

.cursor_done:
  JSR ensure_cursor_visible
  LDA #$FF
  STA MODIFIED
.done:
  JMP clear_count

; Character paste above (before cursor)
char_paste_above:
  JSR get_count              ; BUF_TEMP16 = count
  JSR yank_paste_setup
  BCS .done                  ; Empty yank

  ; Save total paste size on stack
  PUSH16 BUF_LEN16

  ; Insertion point: at cursor position
  JSR get_cursor_buf_ptr

  JSR yank_paste_core
  POP16 BUF_LEN16            ; Recover total paste size
  BCS .done                  ; Paste failed

  ; CURSOR_COL16 = CURSOR_COL16 + BUF_LEN16 - 1
  CLC
  ADC16 CURSOR_COL16, BUF_LEN16, CURSOR_COL16
  DEC16 CURSOR_COL16
  JSR ensure_cursor_visible
  LDA #$FF
  STA MODIFIED
.done:
  JMP clear_count

; --- Toggle case (~) ---
normal_toggle_case:
  JSR get_count
  LDX BUF_TEMP16

.tilde_loop:
  STX NORMAL_TEMP
  JSR check_cursor_in_line
  BCS .tilde_done

  JSR get_cursor_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  CMP #'A'
  BCC .tilde_advance
  CMP #$5B
  BCC .tilde_toggle
  CMP #'a'
  BCC .tilde_advance
  CMP #$7B
  BCS .tilde_advance

.tilde_toggle:
  EOR #$20
  STA (BUF_PTR16),Y
  LDA #$FF
  STA MODIFIED
  LDA #1
  STA RENDER_FLAG

.tilde_advance:
  SEC
  SBCI16 LINE_LEN16, 1, BUF_TEMP16
  CMP16 CURSOR_COL16, BUF_TEMP16
  BCS .tilde_next
  INC16 CURSOR_COL16

.tilde_next:
  LDX NORMAL_TEMP
  DEX
  BNE .tilde_loop

.tilde_done:
  JSR ensure_cursor_visible
  JMP clear_count

; --- Join lines (J) ---
normal_join_lines:
  JSR get_count
  LDX BUF_TEMP16

  TST16 COUNT16
  BEQ .join_start
  DEX
  BEQ .join_done

.join_start:
  STX NORMAL_TEMP

.join_loop:
  CLC
  ADCI16 FILE_LINE16, 1, BUF_PTR16
  CMP16 BUF_PTR16, LINE_COUNT16
  BCS .join_done

  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr
  LDY #0
.join_find_nl:
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .join_found_nl
  INY
  BNE .join_find_nl
  INC BUF_PTR16+1
  JMP .join_find_nl

.join_found_nl:
  LDA #' '
  STA (BUF_PTR16),Y
  JSR buf_rebuild_lines

  LDA #1
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16+1
  CLC
  ADCI16 FILE_LINE16, 1, BUF_PTR16
  LDAX16 BUF_PTR16
  JSR mark_adjust_delete

  DEC NORMAL_TEMP
  BNE .join_loop

  LDA #$FF
  STA MODIFIED
  JSR clamp_cursor_col

.join_done:
  JMP clear_count

; --- Substitute char (s) ---
normal_substitute_char:
  JSR check_cursor_in_line
  BCS .sub_insert

  SEC
  SBC16 LINE_LEN16, CURSOR_COL16, BUF_LEN16
  JSR get_count
  LDA BUF_TEMP16
  CMP BUF_LEN16
  BCC .sub_count_ok
  LDA BUF_LEN16
.sub_count_ok:
  STA BUF_DELTA

  JSR get_cursor_buf_ptr
  CP16 BUF_PTR16, BUF_SRC16
  LDA BUF_DELTA
  STA BUF_LEN16
  LDA #0
  STA BUF_LEN16+1
  JSR yank_add_chars

  JSR get_cursor_buf_ptr
  JSR buf_delete_chars
  JSR buf_adjust_lines_dec

  LDA #$FF
  STA MODIFIED
  LDA #1
  STA RENDER_FLAG

.sub_insert:
  LDA #MODE_INSERT
  STA MODE
  JMP clear_count

; --- Change to EOL (C) ---
normal_change_to_eol:
  JSR check_cursor_in_line
  BCS .c_insert

  SEC
  SBC16 LINE_LEN16, CURSOR_COL16, BUF_LEN16
  JSR yank_delete_at_cursor

.c_insert:
  LDA #MODE_INSERT
  STA MODE
  JMP clear_count

normal_r_key:
  LDA #'r'
  JMP set_pending_key

; --- Replace char (r) ---
do_replace_char:
  JSR get_count
  LDX BUF_TEMP16

.replace_loop:
  STX NORMAL_TEMP
  JSR check_cursor_in_line
  BCS .replace_done

  JSR get_cursor_buf_ptr
  LDY #0
  LDA BUF_TEMP
  STA (BUF_PTR16),Y
  LDA #$FF
  STA MODIFIED
  LDA #1
  STA RENDER_FLAG

  LDX NORMAL_TEMP
  CPX #1
  BEQ .replace_done
  INC16 CURSOR_COL16
  DEX
  BNE .replace_loop

.replace_done:
  JMP clear_count

; --- Change line (cc) ---
; Yank line(s), delete, insert newline, enter insert at col 0.
normal_c_key:
  LDA #'c'
  JMP set_pending_key

; S = substitute line (alias for cc with count=1)
normal_substitute_line:
  LDA #1
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16+1
  JMP cc_have_count

do_cc:
  JSR get_count
cc_have_count:
  JSR yank_delete_current_lines
  BCS .cc_overflow
  ; Check if current line is already empty (from buf_delete_lines empty handling)
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .cc_already_empty

  ; Insert a blank line at FILE_LINE16
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr       ; BUF_PTR16 = start of current line
  LDA #'\n'
  JSR buf_insert_char
  BCS .cc_buf_full
  JSR buf_rebuild_lines

  ; Adjust marks for inserted line
  LDA #1
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16+1
  LDAX16 FILE_LINE16
  JSR mark_adjust_insert

.cc_already_empty:
  LDA #0
  STA_LH16 CURSOR_COL16
  JSR ensure_cursor_visible
  LDA #MODE_INSERT
  STA MODE
  LDA #$FF
  STA MODIFIED
  JMP clear_count

.cc_overflow:
  JMP show_yank_overflow

.cc_buf_full:
  SET16 str_buffer_full, STR_PTR16
  JSR show_status_message
  JMP clear_count

; --- Indent (>>) ---
INDENT_WIDTH = 2

normal_gt_key:
  LDA #'>'
  JMP set_pending_key

normal_lt_key:
  LDA #'<'
  JMP set_pending_key

do_indent:
  JSR get_count
  ; BUF_TEMP16 = count of lines to indent

  ; Clamp count to available lines
  SEC
  SBC16 LINE_COUNT16, FILE_LINE16, BUF_LEN16
  CMP16 BUF_TEMP16, BUF_LEN16
  BCC .indent_count_ok
  CP16 BUF_LEN16, BUF_TEMP16
.indent_count_ok:
  ; BUF_TEMP16 = clamped count
  ; Use LINE_LEN16 as current line number counter
  CP16 FILE_LINE16, LINE_LEN16

.indent_loop:
  TST16 BUF_TEMP16
  BEQ .indent_done_loop

  ; Get line pointer
  LDAX16 LINE_LEN16
  JSR buf_get_line_ptr       ; BUF_PTR16 = start of line

  ; Insert 2 spaces at start of line
  LDA #INDENT_WIDTH
  STA BUF_DELTA
  LDA #' '
  STA BATCH_BUF
  STA BATCH_BUF+1
  JSR buf_insert_chars
  BCS .indent_done_loop      ; Buffer full, stop
  JSR buf_rebuild_lines

  INC16 LINE_LEN16
  DEC16 BUF_TEMP16
  JMP .indent_loop

.indent_done_loop:
  ; Adjust cursor col
  CLC
  ADCI16 CURSOR_COL16, INDENT_WIDTH, CURSOR_COL16
  JSR ensure_cursor_visible
  LDA #$FF
  STA MODIFIED
  JMP clear_count

; --- Unindent (<<) ---
do_unindent:
  JSR get_count

  ; Clamp count to available lines
  SEC
  SBC16 LINE_COUNT16, FILE_LINE16, BUF_LEN16
  CMP16 BUF_TEMP16, BUF_LEN16
  BCC .unindent_count_ok
  CP16 BUF_LEN16, BUF_TEMP16
.unindent_count_ok:
  CP16 FILE_LINE16, LINE_LEN16

.unindent_loop:
  TST16 BUF_TEMP16
  BEQ .unindent_done_loop

  LDAX16 LINE_LEN16
  JSR buf_get_line_ptr

  ; Count leading spaces (up to INDENT_WIDTH)
  LDY #0
  LDA (BUF_PTR16),Y
  CMP #' '
  BNE .unindent_no_remove
  INY
  LDA (BUF_PTR16),Y
  CMP #' '
  BNE .unindent_one
  LDA #2
  JMP .unindent_do_remove
.unindent_one:
  LDA #1
.unindent_do_remove:
  STA BUF_DELTA
  JSR buf_delete_chars
  JSR buf_rebuild_lines

.unindent_no_remove:
  INC16 LINE_LEN16
  DEC16 BUF_TEMP16
  JMP .unindent_loop

.unindent_done_loop:
  ; Adjust cursor col (subtract INDENT_WIDTH, clamp to 0)
  SEC
  SBCI16 CURSOR_COL16, INDENT_WIDTH, CURSOR_COL16
  BCS .unindent_col_ok
  LDA #0
  STA_LH16 CURSOR_COL16
.unindent_col_ok:
  JSR clamp_cursor_col
  JSR ensure_cursor_visible
  LDA #$FF
  STA MODIFIED
  JMP clear_count

; --- Delete word (dw) ---
; Delete from cursor to next word boundary on current line.
; Yanks deleted text. Accepts count.
do_dw:
  JSR get_count
  LDX BUF_TEMP16

.dw_loop:
  STX NORMAL_TEMP
  JSR check_cursor_in_line
  BCS .dw_done

  ; Find forward word boundary
  CP16 CURSOR_COL16, BUF_LEN16   ; BUF_LEN16 = scan position
  JSR get_cursor_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  STA WORD_CLASS
  CMP #0
  BEQ .dw_skip_ws

  ; Skip same-class chars
  JSR skip_word_class_forward
  BCS .dw_have_end
  CMP #0
  BNE .dw_have_end

  ; Skip trailing whitespace
.dw_skip_ws:
  LDA #0
  STA WORD_CLASS
  JSR skip_word_class_forward

.dw_have_end:
  ; delete count = BUF_LEN16 - CURSOR_COL16
  SEC
  SBC16 BUF_LEN16, CURSOR_COL16, BUF_LEN16
  JSR yank_delete_at_cursor

  LDX NORMAL_TEMP
  DEX
  BEQ .dw_done
  JMP .dw_loop

.dw_done:
  JSR clamp_cursor_col
  JMP clear_count

; --- Delete word backward (db) ---
do_db:
  JSR get_count
  LDX BUF_TEMP16

.db_loop:
  STX NORMAL_TEMP
  TST16 CURSOR_COL16
  BNE .db_not_bol          ; Not at col 0, proceed
  JMP .db_done
.db_not_bol:

  JSR find_word_start_backward
  ; BUF_LEN16 = start position. Delete from start to cursor.
  ; Compute delete count and move cursor to start
  PUSH16 BUF_LEN16           ; Save start position
  SEC
  SBC16 CURSOR_COL16, BUF_LEN16, BUF_LEN16   ; BUF_LEN16 = delete count
  POP16 CURSOR_COL16         ; Move cursor to start position
  JSR yank_delete_at_cursor

  LDX NORMAL_TEMP
  DEX
  BEQ .db_done
  JMP .db_loop

.db_done:
  JSR clamp_cursor_col
  JMP clear_count

; --- Change word (cw) ---
; vi's cw = ce: delete to end of current word only (no trailing ws).
; Enter insert mode after deletion.
do_cw:
  JSR get_count
  LDX BUF_TEMP16

.cw_loop:
  STX NORMAL_TEMP
  JSR check_cursor_in_line
  BCS .cw_insert

  ; Find end of current word (no trailing whitespace)
  CP16 CURSOR_COL16, BUF_LEN16
  JSR get_cursor_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  STA WORD_CLASS
  CMP #0
  BEQ .cw_skip_ws_first

  ; Skip same-class chars (no trailing ws for cw)
  JSR skip_word_class_forward
  JMP .cw_have_end

.cw_skip_ws_first:
  ; On whitespace: skip ws, then skip that word class
  JSR skip_word_class_forward
  BCS .cw_have_end
  STA WORD_CLASS
  JSR skip_word_class_forward

.cw_have_end:
  ; delete count = BUF_LEN16 - CURSOR_COL16
  SEC
  SBC16 BUF_LEN16, CURSOR_COL16, BUF_LEN16
  JSR yank_delete_at_cursor

  LDX NORMAL_TEMP
  DEX
  BEQ .cw_insert
  JMP .cw_loop

.cw_insert:
  LDA #MODE_INSERT
  STA MODE
  JMP clear_count

; --- Change word backward (cb) ---
do_cb:
  JSR get_count
  LDX BUF_TEMP16

.cb_loop:
  STX NORMAL_TEMP
  TST16 CURSOR_COL16
  BNE .cb_not_bol
  JMP .cb_insert
.cb_not_bol:

  JSR find_word_start_backward
  ; Compute delete count and move cursor to start
  PUSH16 BUF_LEN16           ; Save start position
  SEC
  SBC16 CURSOR_COL16, BUF_LEN16, BUF_LEN16   ; BUF_LEN16 = delete count
  POP16 CURSOR_COL16         ; Move cursor to start position
  JSR yank_delete_at_cursor

  LDX NORMAL_TEMP
  DEX
  BEQ .cb_insert
  JMP .cb_loop

.cb_insert:
  LDA #MODE_INSERT
  STA MODE
  JMP clear_count
