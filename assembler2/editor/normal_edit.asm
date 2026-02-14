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

  ; available = LINE_LEN16 - CURSOR_COL16
  SEC
  SBC16 LINE_LEN16, CURSOR_COL16, BUF_LEN16
  JSR get_count
  ; Clamp count to available chars
  CMP16 BUF_TEMP16, BUF_LEN16
  BCC .sub_count_ok
  BEQ .sub_count_ok
  CP16 BUF_LEN16, BUF_TEMP16
.sub_count_ok:
  CP16 BUF_TEMP16, BUF_LEN16
  LDA #OP_CHANGE
  JSR apply_char_operator
  RTS

.sub_insert:
  JMP enter_insert_mode

; --- Change to EOL (C) ---
normal_change_to_eol:
  JSR check_cursor_in_line
  BCS .c_insert

  SEC
  SBC16 LINE_LEN16, CURSOR_COL16, BUF_LEN16
  LDA #OP_CHANGE
  JSR apply_char_operator
  RTS

.c_insert:
  JMP enter_insert_mode

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
  DEX
  BEQ .replace_done
  INC16 CURSOR_COL16
  JMP .replace_loop

.replace_done:
  JMP clear_count

; --- Change line (cc) ---
; Yank line(s), delete, insert newline, enter insert at col 0.
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
  LDA #$FF
  STA MODIFIED
  JMP enter_insert_mode

.cc_overflow:
  JMP show_yank_overflow

.cc_buf_full:
  JSR show_buffer_full_msg
  JMP clear_count

; --- Indent (>>) ---
INDENT_WIDTH = 2

do_indent:
  JSR get_count_clamp_lines
  LDA #0
  STA NORMAL_TEMP              ; Cursor-line-indented flag
  STA COUNT16                  ; N_ne = 0 (non-empty line count)
  STA COUNT16+1

  ; --- Pre-scan: count non-empty lines ---
  PUSH16 BUF_TEMP16            ; Save loop count for redistribute

.indent_prescan:
  TST16 BUF_TEMP16
  BEQ .indent_prescan_done

  LDAX16 LINE_LEN16
  JSR buf_get_line_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .indent_prescan_next

  ; Non-empty line
  INC16 COUNT16
  ; Check if cursor line
  CMP16 LINE_LEN16, FILE_LINE16
  BNE .indent_prescan_next
  LDA #$FF
  STA NORMAL_TEMP

.indent_prescan_next:
  INC16 LINE_LEN16
  DEC16 BUF_TEMP16
  JMP .indent_prescan

.indent_prescan_done:
  POP16 BUF_TEMP16             ; Restore loop count
  CP16 FILE_LINE16, LINE_LEN16 ; Reset line counter

  ; If no non-empty lines, nothing to do
  TST16 COUNT16
  BEQ .indent_no_col_adj

  ; total_shift = N_ne * INDENT_WIDTH (= N_ne << 1)
  CP16 COUNT16, BUF_LEN16
  ASL16 BUF_LEN16              ; BUF_LEN16 = total_shift

  ; Get first line start
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr         ; BUF_PTR16 = first line start

  ; Single buffer shift right
  JSR buf_shift_right_16
  BCS .indent_no_col_adj       ; Buffer full, bail

  ; --- Redistribute: insert spaces into non-empty lines ---
  ; BUF_PTR16 = first line start (preserved by buf_shift_right_16)
  ; JUMP_TARGET16 = write_ptr (starts at first line start)
  ; BUF_PTR16 = read_ptr (first line start + total_shift)
  CP16 BUF_PTR16, JUMP_TARGET16
  CLC
  ADC16 BUF_PTR16, BUF_LEN16, BUF_PTR16

.indent_redist:
  TST16 BUF_TEMP16
  BEQ .indent_redist_done

  ; Check first byte of line at read_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .indent_copy_line

  ; Non-empty: write 2 spaces at write_ptr
  LDA #' '
  STA (JUMP_TARGET16),Y       ; Y = 0
  INY
  STA (JUMP_TARGET16),Y
  INC16 JUMP_TARGET16
  INC16 JUMP_TARGET16

.indent_copy_line:
  JSR copy_line_to_nl

  DEC16 BUF_TEMP16
  JMP .indent_redist

.indent_redist_done:
  JSR buf_rebuild_lines

  ; Only adjust cursor col if cursor line was indented
  LDA NORMAL_TEMP
  BEQ .indent_no_col_adj
  CLC
  ADCI16 CURSOR_COL16, INDENT_WIDTH, CURSOR_COL16
.indent_no_col_adj:
  LDA #$FF
  STA RENDER_FLAG        ; Multi-line edit; BUF_END16 change only triggers current-line
  STA MODIFIED
  JMP clear_count

; --- Unindent (<<) ---
do_unindent:
  JSR get_count_clamp_lines
  LDA #0
  STA NORMAL_TEMP              ; Cursor line spaces removed
  STA COUNT16                  ; total_shrink = 0
  STA COUNT16+1

  ; Set write_ptr = first line start
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr
  CP16 BUF_PTR16, JUMP_TARGET16  ; JUMP_TARGET16 = write_ptr

.unindent_loop:
  TST16 BUF_TEMP16
  BEQ .unindent_done_loop

  ; Get line start from LINE_TBL (still valid, no shifts yet)
  LDAX16 LINE_LEN16
  JSR buf_get_line_ptr         ; BUF_PTR16 = line start

  ; Count leading spaces (0, 1, or 2)
  LDY #0
  LDA (BUF_PTR16),Y
  CMP #' '
  BNE .unindent_zero_sp
  INY
  LDA (BUF_PTR16),Y
  CMP #' '
  BNE .unindent_one_sp
  LDA #2
  JMP .unindent_have_sp
.unindent_one_sp:
  LDA #1
  JMP .unindent_have_sp
.unindent_zero_sp:
  LDA #0

.unindent_have_sp:
  ; A = spaces to remove (0, 1, or 2)
  STA BUF_DELTA

  ; If cursor line, save actual removal in NORMAL_TEMP
  CMP16 LINE_LEN16, FILE_LINE16
  BNE .unindent_not_cursor
  LDA BUF_DELTA
  STA NORMAL_TEMP
.unindent_not_cursor:

  ; Add to total_shrink
  LDA BUF_DELTA
  CLC
  ADCA16 COUNT16, COUNT16

  ; Advance BUF_PTR16 past leading spaces
  LDA BUF_DELTA
  CLC
  ADCA16 BUF_PTR16, BUF_PTR16

  ; Copy remaining line (including newline) to write_ptr
  JSR copy_line_to_nl

  INC16 LINE_LEN16
  DEC16 BUF_TEMP16
  JMP .unindent_loop

.unindent_done_loop:
  ; If nothing was removed, skip shift
  TST16 COUNT16
  BEQ .unindent_no_cursor_adj

  ; Single shift left: close the gap after processed range
  CP16 JUMP_TARGET16, BUF_PTR16
  CP16 COUNT16, BUF_LEN16
  JSR buf_shift_left_16
  JSR buf_rebuild_lines

  ; Cursor adjustment: subtract actual spaces removed, clamp to 0
  LDA NORMAL_TEMP
  BEQ .unindent_no_cursor_adj
  LDA CURSOR_COL16
  SEC
  SBC NORMAL_TEMP
  STA CURSOR_COL16
  LDA CURSOR_COL16+1
  SBC #0
  STA CURSOR_COL16+1
  BCS .unindent_col_ok
  LDA #0
  STA_LH16 CURSOR_COL16
.unindent_col_ok:
  JSR clamp_cursor_col

.unindent_no_cursor_adj:
  LDA #$FF
  STA RENDER_FLAG        ; Multi-line edit; BUF_END16 change only triggers current-line
  STA MODIFIED
  JMP clear_count

; Copy bytes from (BUF_PTR16) to (JUMP_TARGET16) until '\n' is copied.
; Advances both pointers past the copied data.
; Clobbers: A, Y
copy_line_to_nl:
  LDY #0
  LDA (BUF_PTR16),Y
  STA (JUMP_TARGET16),Y
  INC16 BUF_PTR16
  INC16 JUMP_TARGET16
  CMP #'\n'
  BNE copy_line_to_nl
  RTS

; --- Delete word (dw) ---
; Delete from cursor to next word boundary on current line.
; Yanks deleted text. Accepts count.
; Non-batched (count prefix): scans N words, single yank+delete (yanks ALL)
; Batched (dwdw...): delete N-1 words (no yank), yank+delete last word
do_dw:
  JSR get_count              ; BUF_TEMP16 = N
  JSR check_cursor_in_line
  BCS .dw_done               ; Empty line, bail

  CP16 CURSOR_COL16, BUF_LEN16  ; BUF_LEN16 = scan start at cursor

  LDA BATCH_EXTRA
  BNE .dw_batched

  ; --- Non-batched: scan N words, single yank+delete ---
  LDX BUF_TEMP16
  JSR scan_words_forward
  SEC
  SBC16 BUF_LEN16, CURSOR_COL16, BUF_LEN16
  TST16 BUF_LEN16
  BEQ .dw_done               ; Nothing to delete
  JSR yank_delete_at_cursor
  JMP .dw_finish

.dw_batched:
  ; --- Batched: delete (N-1) without yank, then yank+delete last word ---
  LDX BUF_TEMP16
  DEX
  BEQ .dw_batch_last         ; N=1, skip first delete
  JSR scan_words_forward
  SEC
  SBC16 BUF_LEN16, CURSOR_COL16, BUF_LEN16
  TST16 BUF_LEN16
  BEQ .dw_batch_last         ; Nothing for first part
  JSR delete_at_cursor       ; 1st shift (no yank)

.dw_batch_last:
  ; Yank+delete last word
  JSR check_cursor_in_line
  BCS .dw_done
  CP16 CURSOR_COL16, BUF_LEN16
  LDX #1
  JSR scan_words_forward
  SEC
  SBC16 BUF_LEN16, CURSOR_COL16, BUF_LEN16
  TST16 BUF_LEN16
  BEQ .dw_done               ; Nothing to delete
  JSR yank_delete_at_cursor   ; 2nd shift (yanks last word)

.dw_finish:
  JSR clamp_cursor_col
.dw_done:
  JMP clear_count

; --- Delete word backward (db) ---
; Delete backward to previous word boundary on current line.
; Yanks deleted text. Accepts count.
; Non-batched (count prefix): scans N words back, single yank+delete (yanks ALL)
; Batched (dbdb...): delete N-1 words (no yank), yank+delete last word
do_db:
  JSR get_count              ; BUF_TEMP16 = N
  TST16 CURSOR_COL16
  BNE .db_not_bol            ; Not at col 0, proceed
  JMP .db_done
.db_not_bol:

  LDA BATCH_EXTRA
  BNE .db_batched

  ; --- Non-batched: scan N words back, single yank+delete ---
  PUSH16 CURSOR_COL16         ; Save original cursor
  LDX BUF_TEMP16
  JSR scan_words_backward     ; CURSOR_COL16 = new position
  POP16 BUF_LEN16             ; BUF_LEN16 = original cursor
  SEC
  SBC16 BUF_LEN16, CURSOR_COL16, BUF_LEN16  ; BUF_LEN16 = delete count
  TST16 BUF_LEN16
  BEQ .db_done
  JSR yank_delete_at_cursor
  JMP .db_finish

.db_batched:
  ; --- Batched: delete (N-1) without yank, then yank+delete last word ---
  LDX BUF_TEMP16
  DEX
  BEQ .db_batch_last          ; N=1, skip first delete
  PUSH16 CURSOR_COL16
  JSR scan_words_backward
  POP16 BUF_LEN16
  SEC
  SBC16 BUF_LEN16, CURSOR_COL16, BUF_LEN16
  TST16 BUF_LEN16
  BEQ .db_batch_last
  JSR delete_at_cursor        ; 1st shift (no yank)

.db_batch_last:
  ; Yank+delete last word
  TST16 CURSOR_COL16
  BEQ .db_done
  PUSH16 CURSOR_COL16
  LDX #1
  JSR scan_words_backward
  POP16 BUF_LEN16
  SEC
  SBC16 BUF_LEN16, CURSOR_COL16, BUF_LEN16
  TST16 BUF_LEN16
  BEQ .db_done
  JSR yank_delete_at_cursor   ; 2nd shift (yanks last word)

.db_finish:
  JSR clamp_cursor_col
.db_done:
  JMP clear_count

; --- Change word (cw) ---
; vi's cw = ce: delete to end of current word only (no trailing ws).
; Enter insert mode after deletion.
; Scans N words then single yank+delete (yanks ALL deleted text).
do_cw:
  JSR get_count              ; BUF_TEMP16 = N
  JSR check_cursor_in_line
  BCS .cw_insert

  CP16 CURSOR_COL16, BUF_LEN16  ; BUF_LEN16 = scan start at cursor
  LDX BUF_TEMP16
  JSR scan_cw_forward
  SEC
  SBC16 BUF_LEN16, CURSOR_COL16, BUF_LEN16
  TST16 BUF_LEN16
  BEQ .cw_insert
  JSR yank_delete_at_cursor

.cw_insert:
  JMP enter_insert_mode_render

; --- Change word backward (cb) ---
; Scans N words back then single yank+delete (yanks ALL deleted text).
do_cb:
  JSR get_count              ; BUF_TEMP16 = N
  TST16 CURSOR_COL16
  BEQ .cb_insert             ; At col 0, just enter insert

  PUSH16 CURSOR_COL16         ; Save original cursor
  LDX BUF_TEMP16
  JSR scan_words_backward     ; CURSOR_COL16 = new position
  POP16 BUF_LEN16             ; BUF_LEN16 = original cursor
  SEC
  SBC16 BUF_LEN16, CURSOR_COL16, BUF_LEN16  ; BUF_LEN16 = delete count
  TST16 BUF_LEN16
  BEQ .cb_insert
  JSR yank_delete_at_cursor

.cb_insert:
  JMP enter_insert_mode_render
