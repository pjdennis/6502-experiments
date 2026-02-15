; Normal mode editing commands - paste, toggle case, join, substitute,
; change line, indent/unindent, word delete/change

; --- Paste ---

normal_paste_below:
  LDA YANK_TYPE
  BEQ .line_paste
  JMP char_paste_below
.line_paste:
  JSR get_count              ; BUF_TEMP16 = count
  JSR count_paste_extras     ; BUF_TEMP16 += extras, BATCH_EXTRA = extras
  LDX BUF_TEMP16             ; X = total count (low byte)
  STX NORMAL_TEMP            ; Save paste count for paste_adjust_marks
  JSR yank_paste_below_n
  BCS .paste_below_done
  JSR paste_adjust_marks
  ; Cursor: yank_paste_below_n does INC16 once; add extras for iterative semantics
  LDA BATCH_EXTRA
  BEQ .paste_below_done
  CLC
  ADCA16 FILE_LINE16, FILE_LINE16
.paste_below_done:
  JMP clear_count

normal_paste_above:
  LDA YANK_TYPE
  BEQ .line_paste
  JMP char_paste_above
.line_paste:
  JSR get_count              ; BUF_TEMP16 = count
  JSR count_paste_extras     ; BUF_TEMP16 += extras
  LDX BUF_TEMP16             ; X = total count (low byte)
  STX NORMAL_TEMP            ; Save paste count for paste_adjust_marks
  JSR yank_paste_above_n
  BCS .paste_above_done
  JSR paste_adjust_marks
  ; No cursor adjustment - yank_paste_above_n doesn't change FILE_LINE16
.paste_above_done:
  JMP clear_count

; Character paste below (after cursor)
; For non-empty lines, inserts after cursor char; for empty lines, inserts at line start
; Handles newlines in yanked content via find_line_for_ptr
char_paste_below:
  JSR get_count              ; BUF_TEMP16 = count
  JSR count_paste_extras     ; BUF_TEMP16 += extras
  JSR do_char_paste_below
  ; No cursor adjustment - contiguous insertion gives same cursor as iterative
  JMP clear_count

; Core char paste below: paste BUF_TEMP16 copies after cursor
; Returns carry set = failed/empty, carry clear = success
do_char_paste_below:
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
  JMP .do_paste

.empty_line:
  JSR get_cursor_buf_ptr     ; Insert at line start

.do_paste:
  PUSH16 BUF_PTR16           ; Save insertion point
  JSR yank_paste_core
  POP16 BUF_PTR16            ; Recover insertion point
  POP16 BUF_LEN16            ; Recover total paste size
  BCS .done                  ; Paste failed (buffer full)

  ; Check if pasted content is multi-line
  JSR yank_has_newline
  BCS .multiline

  ; Single-line: cursor at last pasted byte
  CLC
  ADC16 BUF_PTR16, BUF_LEN16, BUF_PTR16
  DEC16 BUF_PTR16
  JMP .find_pos

.multiline:
  ; Multi-line: cursor at first pasted byte (BUF_PTR16 already set)

.find_pos:
  JSR find_line_for_ptr      ; sets FILE_LINE16, CURSOR_COL16
  JSR clamp_cursor_col
  LDA #$FF
  STA MODIFIED
  CLC
.done:
  RTS

; Character paste above (before cursor)
; Handles newlines in yanked content via find_line_for_ptr
; Single-shift interleaved fill for all yank sizes
char_paste_above:
  JSR get_count              ; BUF_TEMP16 = count C
  JSR count_paste_extras     ; BUF_TEMP16 += extras, BATCH_EXTRA = extras
  JSR yank_paste_setup       ; BUF_LEN16 = total size, YANK_SIZE16 = single size
  BCS .done                  ; Empty yank

  ; Save total count N for fill routines
  LDA BUF_TEMP16
  STA NORMAL_TEMP

  ; Save total paste size on stack
  PUSH16 BUF_LEN16

  ; Insertion point: at cursor position
  JSR get_cursor_buf_ptr

  PUSH16 BUF_PTR16           ; Save insertion point

  ; Single buffer shift
  JSR buf_shift_right_16
  BCS .shift_fail

  ; Choose fill strategy based on yank content
  JSR yank_has_newline
  BCS .do_contiguous

  ; Single-line: interleaved fill
  JSR interleaved_fill
  JMP .fill_done

.do_contiguous:
  ; Multi-line: N contiguous copies
  JSR contiguous_fill

.fill_done:
  JSR buf_rebuild_lines

  ; Recover insertion point and total size
  POP16 BUF_PTR16
  POP16 BUF_LEN16

  ; Cursor positioning
  JSR yank_has_newline
  BCS .multiline

  ; Single-line: cursor at insertion + total_size - 1 - BATCH_EXTRA
  CLC
  ADC16 BUF_PTR16, BUF_LEN16, BUF_PTR16
  DEC16 BUF_PTR16
  LDA BUF_PTR16
  SEC
  SBC BATCH_EXTRA
  STA BUF_PTR16
  LDA BUF_PTR16+1
  SBC #0
  STA BUF_PTR16+1
  JMP .find_pos

.multiline:
  ; Multi-line: cursor at first pasted byte (BUF_PTR16 = insertion point)

.find_pos:
  JSR find_line_for_ptr      ; sets FILE_LINE16, CURSOR_COL16
  JSR clamp_cursor_col
  LDA #$FF
  STA MODIFIED

.done:
  JMP clear_count

.shift_fail:
  POP16 BUF_PTR16            ; Clean up stack
  POP16 BUF_LEN16
  JSR show_buffer_full_msg
  JMP clear_count

; Interleaved fill for single-line char paste above
; Writes iterative-correct pattern into gap:
;   (C-1) full copies, (E+1) prefixes [0..S-2], (E+1) last bytes [S-1]
; Input: BUF_PTR16 = write position (gap start)
;        NORMAL_TEMP = total count N, BATCH_EXTRA = extras E
;        YANK_SIZE16 = single yank size S (low byte, assumed < 256)
; Clobbers: A, X, Y, NORMAL_TEMP
interleaved_fill:
  ; Phase 1: (C-1) full copies where C = N - E
  LDA NORMAL_TEMP
  SEC
  SBC BATCH_EXTRA
  SBC #1                     ; A = C - 1
  BEQ .phase2
  TAX                        ; X = loop counter

.full_loop:
  LDY #0
.full_byte:
  LDA YANK_BUF,Y
  STA (BUF_PTR16),Y
  INY
  CPY YANK_SIZE16
  BNE .full_byte
  ; Advance write ptr by S
  TYA
  CLC
  ADCA16 BUF_PTR16, BUF_PTR16
  DEX
  BNE .full_loop

.phase2:
  ; (E+1) copies of prefix (first S-1 bytes)
  LDA YANK_SIZE16
  SEC
  SBC #1                     ; A = prefix size = S - 1
  BEQ .phase3                ; S=1, no prefix to write
  STA NORMAL_TEMP            ; Repurpose NORMAL_TEMP = prefix size
  LDX BATCH_EXTRA
  INX                        ; X = E + 1

.prefix_loop:
  LDY #0
.prefix_byte:
  LDA YANK_BUF,Y
  STA (BUF_PTR16),Y
  INY
  CPY NORMAL_TEMP
  BNE .prefix_byte
  ; Advance write ptr by prefix size
  TYA
  CLC
  ADCA16 BUF_PTR16, BUF_PTR16
  DEX
  BNE .prefix_loop

.phase3:
  ; (E+1) copies of last byte yank[S-1]
  LDY YANK_SIZE16
  DEY                        ; Y = S - 1
  LDA YANK_BUF,Y             ; A = last byte
  LDX BATCH_EXTRA
  INX                        ; X = E + 1
  LDY #0
.suffix_loop:
  STA (BUF_PTR16),Y
  INY
  DEX
  BNE .suffix_loop
  RTS

; Contiguous fill: write N copies of yank buffer at BUF_PTR16
; Input: BUF_PTR16 = write position, NORMAL_TEMP = count N
; Clobbers: A, X, Y, BUF_SRC16, BUF_DST16
contiguous_fill:
  LDX NORMAL_TEMP
.loop:
  PUSH16 BUF_PTR16           ; Save write position
  CP16 BUF_PTR16, BUF_DST16  ; BUF_DST16 = write position
  SET16 YANK_BUF, BUF_SRC16
  CP16 YANK_END16, BUF_PTR16 ; BUF_PTR16 = end of yank data
  TXA
  PHA                        ; Save loop counter
  JSR mem_copy_down
  PLA
  TAX                        ; Restore loop counter
  POP16 BUF_PTR16            ; Restore write position
  ; Advance write position by single yank size
  CLC
  ADC16 BUF_PTR16, YANK_SIZE16, BUF_PTR16
  DEX
  BNE .loop
  RTS

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
  JSR find_line_end
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
; Delete from cursor to next word boundary (multi-line).
; Yanks deleted text. Accepts count.
; Non-batched (count prefix): scans N words, single yank+delete (yanks ALL)
; Batched (dwdw...): delete N-1 words (no yank), yank+delete last word
do_dw:
  JSR get_count              ; BUF_TEMP16 = N
  JSR check_cursor_in_line
  BCS .dw_done               ; Empty line, bail
  LDA BATCH_EXTRA
  BNE .dw_batched

  ; Non-batched: single compute + yank+delete
  LDX BUF_TEMP16
  JSR compute_multiline_word_range_forward
  BCS .dw_done
  LDA #OP_DELETE
  JSR apply_char_operator
  JMP .dw_finish

.dw_batched:
  ; Delete (total-1) words without yank
  LDX BUF_TEMP16
  DEX
  BEQ .dw_batch_last
  JSR compute_multiline_word_range_forward
  BCS .dw_batch_last
  JSR delete_at_cursor

.dw_batch_last:
  ; Re-check line after deletions
  JSR check_cursor_in_line
  BCS .dw_done
  LDX #1
  JSR compute_multiline_word_range_forward
  BCS .dw_done
  LDA #OP_DELETE
  JSR apply_char_operator

.dw_finish:
  JSR clamp_cursor_col
.dw_done:
  JMP clear_count

; --- Delete word backward (db) ---
; Delete backward to previous word boundary (multi-line).
; Yanks deleted text. Accepts count.
; Non-batched (count prefix): scans N words back, single yank+delete (yanks ALL)
; Batched (dbdb...): delete N-1 words (no yank), yank+delete last word
do_db:
  JSR get_count              ; BUF_TEMP16 = N
  ; Bail only at file start (col 0 AND line 0)
  TST16 CURSOR_COL16
  BNE .db_ok
  TST16 FILE_LINE16
  BEQ .db_done               ; At file start, nothing to do
.db_ok:
  LDA BATCH_EXTRA
  BNE .db_batched

  ; Non-batched
  LDX BUF_TEMP16
  JSR compute_multiline_word_range_backward
  BCS .db_done
  LDA #OP_DELETE
  JSR apply_char_operator
  JMP .db_finish

.db_batched:
  LDX BUF_TEMP16
  DEX
  BEQ .db_batch_last
  JSR compute_multiline_word_range_backward
  BCS .db_batch_last
  JSR delete_at_cursor

.db_batch_last:
  ; Re-check: still have room to go backward?
  TST16 CURSOR_COL16
  BNE .db_batch_ok
  TST16 FILE_LINE16
  BEQ .db_done
.db_batch_ok:
  LDX #1
  JSR compute_multiline_word_range_backward
  BCS .db_done
  LDA #OP_DELETE
  JSR apply_char_operator

.db_finish:
  JSR clamp_cursor_col
.db_done:
  JMP clear_count

; --- Change word (cw) ---
; vi's cw = ce: delete to end of current word only (no trailing ws).
; Enter insert mode after deletion. Multi-line.
; Scans N words then single yank+delete (yanks ALL deleted text).
do_cw:
  JSR get_count              ; BUF_TEMP16 = N
  JSR check_cursor_in_line
  BCS .cw_insert
  LDX BUF_TEMP16
  JSR compute_multiline_cw_range_forward
  BCS .cw_insert
  LDA #OP_CHANGE
  JSR apply_char_operator
  RTS
.cw_insert:
  JMP enter_insert_mode_render

; --- Change word backward (cb) ---
; Scans N words back then single yank+delete (yanks ALL deleted text). Multi-line.
do_cb:
  JSR get_count              ; BUF_TEMP16 = N
  ; Bail only at file start (col 0 AND line 0)
  TST16 CURSOR_COL16
  BNE .cb_ok
  TST16 FILE_LINE16
  BEQ .cb_insert
.cb_ok:
  LDX BUF_TEMP16
  JSR compute_multiline_word_range_backward
  BCS .cb_insert
  LDA #OP_CHANGE
  JSR apply_char_operator
  RTS
.cb_insert:
  JMP enter_insert_mode_render

; --- Delete word end (de) ---
; Delete from cursor to end of word (inclusive, multi-line).
; Yanks deleted text. Accepts count.
; Non-batched (count prefix): scans N words, single yank+delete (yanks ALL)
; Batched (dede...): delete N-1 words (no yank), yank+delete last word
do_de:
  JSR get_count              ; BUF_TEMP16 = N
  JSR check_cursor_in_line
  BCS .de_done               ; Empty line, bail
  LDA BATCH_EXTRA
  BNE .de_batched

  ; Non-batched: single compute + yank+delete
  LDX BUF_TEMP16
  JSR compute_multiline_word_end_range_forward
  BCS .de_done
  LDA #OP_DELETE
  JSR apply_char_operator
  JMP .de_finish

.de_batched:
  ; Delete (total-1) words without yank
  LDX BUF_TEMP16
  DEX
  BEQ .de_batch_last
  JSR compute_multiline_word_end_range_forward
  BCS .de_batch_last
  JSR delete_at_cursor

.de_batch_last:
  ; Re-check line after deletions
  JSR check_cursor_in_line
  BCS .de_done
  LDX #1
  JSR compute_multiline_word_end_range_forward
  BCS .de_done
  LDA #OP_DELETE
  JSR apply_char_operator

.de_finish:
  JSR clamp_cursor_col
.de_done:
  JMP clear_count

; --- Change word end (ce) ---
; Delete from cursor to end of word (inclusive, multi-line), enter insert mode.
; Scans N words then single yank+delete (yanks ALL deleted text).
do_ce:
  JSR get_count              ; BUF_TEMP16 = N
  JSR check_cursor_in_line
  BCS .ce_insert
  LDX BUF_TEMP16
  JSR compute_multiline_word_end_range_forward
  BCS .ce_insert
  LDA #OP_CHANGE
  JSR apply_char_operator
  RTS
.ce_insert:
  JMP enter_insert_mode_render
