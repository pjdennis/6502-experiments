; Normal mode editing commands - paste, toggle case, join, substitute,
; change line, indent/unindent, word delete/change

; --- Paste ---

normal_paste_below:
  JSR undo_clear
  LDA YANK_TYPE
  BEQ .line_paste
  JMP char_paste_below
.line_paste:
  CP16 FILE_LINE16, UNDO_LINE16
  CP16 CURSOR_COL16, UNDO_COL16
  JSR get_count              ; BUF_TEMP16 = count
  JSR count_paste_extras     ; BUF_TEMP16 += extras, BATCH_EXTRA = extras
  CP16 BUF_TEMP16, UNDO_PASTE_COUNT16
  PUSH16 BUF_TEMP16          ; Save paste count for paste_adjust_marks
  JSR yank_paste_below_n
  POP16 BUF_TEMP16           ; Restore paste count (carry preserved by PLA/STA)
  BCS .paste_below_done
  JSR paste_adjust_marks
  LDA #UNDO_LINE_PASTE_BELOW
  STA UNDO_TYPE
  ; Cursor: yank_paste_below_n does INC16 once; add extras for iterative semantics
  LDA BATCH_EXTRA
  BEQ .paste_below_scroll
  ; Batched paste: cursor adjustment shifts FILE_LINE16 past first pasted
  ; lines, so scroll walk would start at wrong position.
  CLC
  ADCA16 FILE_LINE16, FILE_LINE16
  JMP .paste_below_done           ; RENDER_FLAG stays 0 → full repaint
.paste_below_scroll:
  LDA #$03
  STA RENDER_FLAG        ; Signal line-insert for scroll optimization
.paste_below_done:
  JMP clear_count

normal_paste_above:
  JSR undo_clear
  LDA YANK_TYPE
  BEQ .line_paste
  JMP char_paste_above
.line_paste:
  CP16 FILE_LINE16, UNDO_LINE16
  CP16 CURSOR_COL16, UNDO_COL16
  JSR get_count              ; BUF_TEMP16 = count
  JSR count_paste_extras     ; BUF_TEMP16 += extras
  CP16 BUF_TEMP16, UNDO_PASTE_COUNT16
  PUSH16 BUF_TEMP16          ; Save paste count for paste_adjust_marks
  JSR yank_paste_above_n
  POP16 BUF_TEMP16           ; Restore paste count (carry preserved by PLA/STA)
  BCS .paste_above_done
  JSR paste_adjust_marks
  LDA #UNDO_LINE_PASTE_ABOVE
  STA UNDO_TYPE
  LDA #$03
  STA RENDER_FLAG        ; Signal line-insert for scroll optimization
  ; No cursor adjustment - yank_paste_above_n doesn't change FILE_LINE16
.paste_above_done:
  JMP clear_count

; Character paste below (after cursor)
; For non-empty lines, inserts after cursor char; for empty lines, inserts at line start
; Handles newlines in yanked content via find_line_for_ptr
char_paste_below:
  CP16 FILE_LINE16, UNDO_LINE16
  JSR get_count              ; BUF_TEMP16 = count
  JSR count_paste_extras     ; BUF_TEMP16 += extras
  CP16 BUF_TEMP16, UNDO_PASTE_COUNT16
  ; Compute insertion column for undo: cursor+1 (non-empty) or 0 (empty)
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .cpb_empty
  CLC
  ADCI16 CURSOR_COL16, 1, UNDO_COL16
  JMP .cpb_paste
.cpb_empty:
  LDA #0
  STA_LH16 UNDO_COL16
.cpb_paste:
  JSR do_char_paste_below
  BCS .cpb_done
  LDA #UNDO_CHAR_PASTE_BELOW
  STA UNDO_TYPE
.cpb_done:
  JMP clear_count

; Core char paste below: paste BUF_TEMP16 copies after cursor
; Returns carry set = failed/empty, carry clear = success
do_char_paste_below:
  JSR yank_paste_setup
  BCC .not_empty
  RTS                          ; Empty yank (carry set)
.not_empty:

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
  CP16 CURSOR_COL16, RENDER_FROM_COL16
  JMP .do_paste

.empty_line:
  JSR get_cursor_buf_ptr     ; Insert at line start

.do_paste:
  CP16 LINE_COUNT16, COUNT16 ; Save line count for mark adjustment
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
  ; Adjust marks for inserted lines (paste below: at_line = FILE_LINE16 + 1)
  SEC
  SBC16 LINE_COUNT16, COUNT16, BUF_TEMP16
  LDAX16 FILE_LINE16
  CLC
  ADC #1
  BCC .mark_adj
  INX
.mark_adj:
  JSR mark_adjust_insert
  ; Skip cursor row in scroll region (save/restore BUF_PTR16 across buf_get_line_len)
  PUSH16 BUF_PTR16
  LDAX16 FILE_LINE16
  JSR buf_get_line_len
  JSR line_screen_rows
  STA PREV_LINE_ROWS
  POP16 BUF_PTR16
  LDA #$09
  STA RENDER_FLAG            ; Line-insert scroll, skip cursor row
  ; INSERT_LINE_COUNT = new_lines + 1 (for split cursor line)
  LDA BUF_TEMP16
  CLC
  ADC #1
  STA INSERT_LINE_COUNT
  ; Cursor at first pasted byte (BUF_PTR16 already set)

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
  CP16 FILE_LINE16, UNDO_LINE16
  CP16 CURSOR_COL16, UNDO_COL16
  JSR get_count              ; BUF_TEMP16 = count C
  JSR count_paste_extras     ; BUF_TEMP16 += extras, BATCH_EXTRA = extras
  CP16 BUF_TEMP16, UNDO_PASTE_COUNT16
  JSR do_char_paste_above
  BCS .cpa_done
  LDA #UNDO_CHAR_PASTE_ABOVE
  STA UNDO_TYPE
.cpa_done:
  JMP clear_count

; Core char paste above: paste BUF_TEMP16 copies at cursor
; Input: BUF_TEMP16 = count, BATCH_EXTRA = extras
; Returns carry set = failed/empty, carry clear = success
do_char_paste_above:
  JSR yank_paste_setup       ; BUF_LEN16 = total size, YANK_SIZE16 = single size
  BCC .not_empty
  RTS                        ; Empty yank (carry set)
.not_empty:

  ; Save total count N for fill routines
  LDA BUF_TEMP16
  STA NORMAL_TEMP

  ; Save total paste size on stack
  PUSH16 BUF_LEN16

  ; Insertion point: at cursor position
  JSR get_cursor_buf_ptr
  CP16 CURSOR_COL16, RENDER_FROM_COL16

  PUSH16 BUF_PTR16           ; Save insertion point
  CP16 LINE_COUNT16, COUNT16 ; Save line count for mark adjustment

  ; Single buffer shift
  JSR buf_shift_right_16
  BCC .shift_ok
  JMP .shift_fail
.shift_ok:

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
  ; Adjust marks for inserted lines
  SEC
  SBC16 LINE_COUNT16, COUNT16, BUF_TEMP16
  LDAX16 FILE_LINE16
  CLC
  JSR mark_adjust_col
  ; Skip cursor row in scroll region (save/restore BUF_PTR16 across buf_get_line_len)
  PUSH16 BUF_PTR16
  LDAX16 FILE_LINE16
  JSR buf_get_line_len
  JSR line_screen_rows
  STA PREV_LINE_ROWS
  POP16 BUF_PTR16
  LDA #$09
  STA RENDER_FLAG            ; Line-insert scroll, skip cursor row
  ; INSERT_LINE_COUNT = new_lines + 1 (for split cursor line)
  LDA BUF_TEMP16
  CLC
  ADC #1
  STA INSERT_LINE_COUNT
  ; Cursor at first pasted byte (BUF_PTR16 = insertion point)

.find_pos:
  JSR find_line_for_ptr      ; sets FILE_LINE16, CURSOR_COL16
  JSR clamp_cursor_col
  LDA #$FF
  STA MODIFIED
  CLC
  RTS

.shift_fail:
  POP16 BUF_PTR16            ; Clean up stack
  POP16 BUF_LEN16
  JSR show_buffer_full_msg
  SEC
  RTS

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
  JSR undo_clear
  JSR get_batched_count
  CP16 CURSOR_COL16, RENDER_FROM_COL16

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
  JSR io_write             ; direct write toggled char
  LDA #$FF
  STA MODIFIED

.tilde_advance:
  SEC
  SBCI16 LINE_LEN16, 1, BUF_TEMP16
  CMP16 CURSOR_COL16, BUF_TEMP16
  BCS .tilde_done            ; at end of line, stop
  INC16 CURSOR_COL16

.tilde_next:
  LDX NORMAL_TEMP
  DEX
  BNE .tilde_loop

.tilde_done:
  JMP clear_count

; --- Join lines (J) ---
normal_join_lines:
  JSR undo_clear
  JSR get_batched_count

  ; Detect batching: BUF_DELTA = count prefix, X = total (count + pending)
  ; If X > BUF_DELTA, there are pending keys (batching)
  TXA
  SEC
  SBC BUF_DELTA              ; A = pending count
  STA UNDO_COL16             ; Repurpose: nonzero = batching

  ; Adjust for explicit count: NJ joins N-1 lines
  LDA COUNT16
  ORA COUNT16 + 1
  BEQ .join_start
  DEX
  BNE .join_start
  JMP .join_done

.join_start:
  STX NORMAL_TEMP            ; NORMAL_TEMP = number of joins to do

  ; Clamp to available lines: can join at most LINE_COUNT16 - FILE_LINE16 - 1
  SEC
  SBC16 LINE_COUNT16, FILE_LINE16, BUF_TEMP16
  DEC16 BUF_TEMP16           ; BUF_TEMP16 = available joins
  LDA BUF_TEMP16 + 1
  BNE .clamp_ok              ; > 255 available, no clamp needed
  LDA NORMAL_TEMP
  CMP BUF_TEMP16
  BCC .clamp_ok
  BEQ .clamp_ok
  LDA BUF_TEMP16
  STA NORMAL_TEMP
.clamp_ok:
  LDA NORMAL_TEMP
  BNE .join_has_work
  JMP .join_done
.join_has_work:

  ; Pre-compute old_total screen rows for displacement-based scroll
  CP16 FILE_LINE16, RENDER_LINE16
  LDA NORMAL_TEMP
  CLC
  ADC #1           ; +1 for cursor line
  JSR compute_delete_screen_rows

  ; Compute undo_count: if batching → 1, else → NORMAL_TEMP
  LDA UNDO_COL16             ; batching flag
  BEQ .no_batch
  LDA #1
  JMP .set_undo_count
.no_batch:
  LDA NORMAL_TEMP
.set_undo_count:
  STA UNDO_JOIN_COUNT

  ; Limit check: undo_count must fit in JOIN_UNDO_BUF
  CMP #JOIN_UNDO_MAX + 1
  BCC .join_limit_ok
  JMP .join_limit_exceeded
.join_limit_ok:

  ; Record undo state
  CP16 FILE_LINE16, UNDO_LINE16
  LDA #UNDO_JOIN
  STA UNDO_TYPE
  LDA #0
  STA UNDO_IS_REDO

  ; Get line start for offset calculations
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr        ; BUF_PTR16 = line start
  CP16 BUF_PTR16, BUF_SRC16  ; BUF_SRC16 = line start (base for offsets)

  JSR find_line_end           ; (BUF_PTR16),Y points to '\n'
  ; Set cursor to join point (end of original first line)
  STY CURSOR_COL16
  STX CURSOR_COL16 + 1
  ; Advance BUF_PTR16 by Y so BUF_PTR16 points directly to the '\n'
  TYA
  CLC
  ADCA16 BUF_PTR16, BUF_PTR16

  LDX #0                     ; X = undo buffer write index
  LDA NORMAL_TEMP
  STA BUF_TEMP               ; loop counter

  ; Single pass: scan forward replacing newlines with spaces
.join_loop:
  LDY #0
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BNE .join_next
  ; Record offset in undo buffer: offset = BUF_PTR16 - BUF_SRC16
  SEC
  LDA BUF_PTR16
  SBC BUF_SRC16
  STA JOIN_UNDO_BUF,X
  LDA BUF_PTR16 + 1
  SBC BUF_SRC16 + 1
  STA JOIN_UNDO_BUF + 1,X
  ; Advance write index only if not batching
  LDA UNDO_COL16             ; batching flag
  BNE .skip_advance
  INX
  INX
.skip_advance:
  ; Replace newline with space
  LDA #' '
  STA (BUF_PTR16),Y
  DEC BUF_TEMP
  BEQ .join_finish
.join_next:
  INC16 BUF_PTR16
  JMP .join_loop

.join_finish:
  ; For batched joins, cursor goes to last join point
  LDA UNDO_COL16             ; batching flag
  BEQ .cursor_done
  SEC
  SBC16 BUF_PTR16, BUF_SRC16, CURSOR_COL16
.cursor_done:
  ; Save join-point cursor for redo
  CP16 CURSOR_COL16, UNDO_COL16
  ; Single rebuild
  JSR buf_rebuild_lines

  ; Single mark adjust for all removed lines
  LDA NORMAL_TEMP
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16+1
  LDAX16 FILE_LINE16
  CLC
  ADC #1
  BCC .mark_adj
  INX
.mark_adj:
  JSR mark_adjust_delete

  LDA #$FF
  STA MODIFIED
  LDA #$06
  STA RENDER_FLAG        ; Signal line-delete, skip cursor row scroll
  JSR clamp_cursor_col

.join_done:
  JMP clear_count

.join_limit_exceeded:
  SET16 str_join_limit, STR_PTR16
  JSR show_status_message
  JMP clear_count

str_join_limit: .asciiz "Too many lines to join"

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
  CP16 CURSOR_COL16, RENDER_FROM_COL16
  LDA #OP_CHANGE
  JSR apply_char_operator
  RTS

.sub_insert:
  JMP enter_insert_mode

; --- Change to EOL (C) ---
normal_change_to_eol:
  JSR check_cursor_in_line
  BCS .c_insert

  JSR get_count
  JSR compute_dollar_range
  CP16 CURSOR_COL16, RENDER_FROM_COL16
  LDA #OP_CHANGE
  JSR apply_char_operator
  RTS

.c_insert:
  JMP enter_insert_mode

; --- Replace char (r) ---
do_replace_char:
  JSR undo_clear
  JSR get_count
  LDX BUF_TEMP16
  CP16 CURSOR_COL16, RENDER_FROM_COL16

.replace_loop:
  STX NORMAL_TEMP
  JSR check_cursor_in_line
  BCS .replace_done

  JSR get_cursor_buf_ptr
  LDY #0
  LDA BUF_TEMP
  STA (BUF_PTR16),Y
  ; Direct write if printable
  CMP #' '
  BCC .replace_need_render
  CMP #$7F
  BCS .replace_need_render
  JSR io_write
  JMP .replace_modified

.replace_need_render:
  LDA #1
  STA RENDER_FLAG

.replace_modified:
  LDA #$FF
  STA MODIFIED

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
  JSR get_count
  JMP cc_have_count

do_cc:
  JSR get_count
cc_have_count:
  ; Pre-compute screen rows for displacement-based scroll
  LDA BUF_TEMP16 + 1
  BNE .cc_skip_precompute    ; Count > 255, skip
  CP16 FILE_LINE16, RENDER_LINE16
  LDA BUF_TEMP16
  JSR compute_delete_screen_rows
  JMP .cc_after_precompute
.cc_skip_precompute:
  LDA #0
  STA DELETE_SCREEN_ROWS
.cc_after_precompute:
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
  LDAX16 FILE_LINE16
  JSR mark_insert_one
  JSR undo_record_cc         ; Upgrade line-delete undo to cc type (blank inserted)
  LDA #$06
  JMP .cc_set_render

.cc_already_empty:
  ; No blank inserted - next line was already empty.
  ; Use $02 (standard delete-scroll) instead of $06 (displacement-based)
  ; because displacement=0 would cause $06 to skip the scroll.
  LDA #$02
.cc_set_render:
  STA RENDER_FLAG
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
  JSR undo_clear
  ; Compute BUF_DELTA = INDENT_WIDTH * (1 + BATCH_EXTRA) = spaces per non-empty line
  LDA BATCH_EXTRA
  CLC
  ADC #1                       ; A = 1 + BATCH_EXTRA
  STA BUF_DELTA                ; temp = repeat_count
  LDA #0
  LDX #INDENT_WIDTH
.indent_mul_bd:
  CLC
  ADC BUF_DELTA
  DEX
  BNE .indent_mul_bd
  STA BUF_DELTA                ; BUF_DELTA = INDENT_WIDTH * repeat_count

  ; Undo batch_pending_pairs COUNT16 addition (>> count = line count, not repeat)
  LDA BATCH_EXTRA
  BEQ .indent_no_undo
  LDA COUNT16
  SEC
  SBC BATCH_EXTRA
  STA COUNT16
  LDA COUNT16+1
  SBC #0
  STA COUNT16+1
.indent_no_undo:
  JSR get_count_clamp_lines
  CP16 FILE_LINE16, LINE_LEN16

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
  BNE .indent_has_ne
  JMP .indent_no_col_adj
.indent_has_ne:

  ; total_shift = N_ne * BUF_DELTA
  LDA #0
  STA BUF_LEN16
  STA BUF_LEN16+1              ; BUF_LEN16 = 0
  LDX BUF_DELTA
.indent_mul_ts:
  CLC
  ADC16 BUF_LEN16, COUNT16, BUF_LEN16
  DEX
  BNE .indent_mul_ts
  ; BUF_LEN16 = total_shift

  ; Get first line start
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr         ; BUF_PTR16 = first line start

  ; Single buffer shift right
  JSR buf_shift_right_16
  BCS .indent_no_col_adj       ; Buffer full, bail

  ; --- Redistribute: insert spaces into non-empty lines ---
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

  ; Non-empty: write BUF_DELTA spaces at write_ptr
  LDY #0
  LDX BUF_DELTA
.indent_write_sp:
  LDA #' '
  STA (JUMP_TARGET16),Y
  INY
  DEX
  BNE .indent_write_sp
  ; Advance write_ptr by BUF_DELTA
  LDA BUF_DELTA
  CLC
  ADCA16 JUMP_TARGET16, JUMP_TARGET16

.indent_copy_line:
  JSR copy_line_to_nl

  DEC16 BUF_TEMP16
  JMP .indent_redist

.indent_redist_done:
  JSR buf_rebuild_lines

  ; Only adjust cursor col if cursor line was indented
  LDA NORMAL_TEMP
  BEQ .indent_no_col_adj
  LDA BUF_DELTA
  CLC
  ADCA16 CURSOR_COL16, CURSOR_COL16
.indent_no_col_adj:
  LDA #$FF
  STA RENDER_FLAG        ; Multi-line edit; BUF_END16 change only triggers current-line
  STA MODIFIED
  JMP clear_count

; --- Unindent (<<) ---
do_unindent:
  JSR undo_clear
  ; Compute BUF_DELTA = INDENT_WIDTH * (1 + BATCH_EXTRA) = max spaces to remove per line
  LDA BATCH_EXTRA
  CLC
  ADC #1                       ; A = 1 + BATCH_EXTRA
  STA BUF_DELTA                ; temp = repeat_count
  LDA #0
  LDX #INDENT_WIDTH
.unindent_mul_bd:
  CLC
  ADC BUF_DELTA
  DEX
  BNE .unindent_mul_bd
  STA BUF_DELTA                ; BUF_DELTA = INDENT_WIDTH * repeat_count

  ; Undo batch_pending_pairs COUNT16 addition (<< count = line count, not repeat)
  LDA BATCH_EXTRA
  BEQ .unindent_no_undo
  LDA COUNT16
  SEC
  SBC BATCH_EXTRA
  STA COUNT16
  LDA COUNT16+1
  SBC #0
  STA COUNT16+1
.unindent_no_undo:
  JSR get_count_clamp_lines
  CP16 FILE_LINE16, LINE_LEN16

  LDA #0
  STA NORMAL_TEMP              ; Cursor line total spaces removed
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

  ; Count leading spaces up to BUF_DELTA
  LDY #0
.unindent_count_sp:
  CPY BUF_DELTA
  BCS .unindent_have_sp
  LDA (BUF_PTR16),Y
  CMP #' '
  BNE .unindent_have_sp
  INY
  JMP .unindent_count_sp
.unindent_have_sp:
  ; Y = spaces to remove for this line (0..BUF_DELTA)

  ; If cursor line, save actual removal in NORMAL_TEMP
  CMP16 LINE_LEN16, FILE_LINE16
  BNE .unindent_not_cursor
  STY NORMAL_TEMP
.unindent_not_cursor:

  ; Add Y to total_shrink
  TYA
  CLC
  ADCA16 COUNT16, COUNT16

  ; Advance BUF_PTR16 past leading spaces
  TYA
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

; --- Dollar motion operations: d$, y$, d0, y0 ---

; d0 handler: delete from BOL to cursor (count ignored)
do_d_zero:
  TST16 CURSOR_COL16
  BEQ .done                   ; Already at col 0, nothing to delete
  ; BUF_LEN16 = CURSOR_COL16 (bytes from BOL to cursor)
  CP16 CURSOR_COL16, BUF_LEN16
  ; Move cursor to col 0 (delete is forward from cursor)
  LDA #0
  STA_LH16 CURSOR_COL16
  LDA #OP_DELETE
  JSR apply_char_operator
.done:
  JMP clear_count

; y0 handler: yank from BOL to cursor (count ignored)
do_y_zero:
  TST16 CURSOR_COL16
  BEQ .done                   ; Already at col 0, nothing to yank
  ; Save cursor col, move to 0 for yank, then restore
  PUSH16 CURSOR_COL16
  CP16 CURSOR_COL16, BUF_LEN16
  LDA #0
  STA_LH16 CURSOR_COL16
  LDA #OP_YANK
  JSR apply_char_operator
  POP16 CURSOR_COL16
.done:
  JMP clear_count

; y$ handler: yank from cursor to EOL, with count support
do_y_dollar:
  JSR get_count
  JSR check_cursor_in_line
  BCS .done
  JSR compute_dollar_range
  LDA #OP_YANK
  JSR apply_char_operator
.done:
  JMP clear_count

; d$ handler: delete from cursor to EOL, with count support
do_d_dollar:
  JSR get_count
  JSR check_cursor_in_line
  BCS .done
  JSR compute_dollar_range
  LDA #OP_DELETE
  JSR apply_char_operator
.done:
  JMP clear_count

; Compute byte range for $ motion with count
; Input: BUF_TEMP16 = count (from get_count), LINE_LEN16 set by check_cursor_in_line
; Output: BUF_LEN16 = byte count from cursor to end of range
; For count=1: BUF_LEN16 = LINE_LEN16 - CURSOR_COL16
; For count>1: adds newline + line_length for each additional line
compute_dollar_range:
  ; Start with current line remainder
  SEC
  SBC16 LINE_LEN16, CURSOR_COL16, BUF_LEN16

  ; Check if count > 1
  LDA BUF_TEMP16 + 1
  BNE .multiline              ; count > 255
  LDA BUF_TEMP16
  CMP #2
  BCC .done                   ; count = 1, done

.multiline:
  ; remaining = count - 1
  SEC
  SBCI16 BUF_TEMP16, 1, BUF_TEMP16
  ; next_line = FILE_LINE16 + 1
  CLC
  ADCI16 FILE_LINE16, 1, COUNT16

.add_line:
  ; Check bounds: if next_line >= LINE_COUNT16, stop
  CMP16 COUNT16, LINE_COUNT16
  BCS .done

  ; Add 1 for the newline
  CLC
  ADCI16 BUF_LEN16, 1, BUF_LEN16

  ; Get length of this line
  LDAX16 COUNT16
  JSR buf_get_line_len
  ; A = low byte, X = high byte of line length
  CLC
  ADC BUF_LEN16
  STA BUF_LEN16
  TXA
  ADC BUF_LEN16 + 1
  STA BUF_LEN16 + 1

  ; Next line
  INC16 COUNT16
  DEC16 BUF_TEMP16
  TST16 BUF_TEMP16
  BNE .add_line

.done:
  RTS

; --- Word operations: delete, change ---
; All word operations are thin wrappers that set up the range function
; and operator type, then delegate to word_op_forward/word_op_backward.

; dw: delete N words forward
do_dw:
  SET16 compute_multiline_word_range_forward, JUMP_TARGET16
  LDA #OP_DELETE
  JMP word_op_forward

; db: delete N words backward
do_db:
  LDA #OP_DELETE
  JMP word_op_backward

; cw: change N words forward (vi cw = ce range)
do_cw:
  SET16 compute_multiline_cw_range_forward, JUMP_TARGET16
  LDA #OP_CHANGE
  JMP word_op_forward

; cb: change N words backward
do_cb:
  LDA #OP_CHANGE
  JMP word_op_backward

; de: delete to end of N words forward
do_de:
  SET16 compute_multiline_word_end_range_forward, JUMP_TARGET16
  LDA #OP_DELETE
  JMP word_op_forward

; ce: change to end of N words forward
do_ce:
  SET16 compute_multiline_word_end_range_forward, JUMP_TARGET16
  LDA #OP_CHANGE
  JMP word_op_forward

; --- Shared word operation helpers ---

; Forward word operation: handles delete, yank, and change for w/e motions.
; Input: JUMP_TARGET16 = range computation function
;        A = operator (OP_DELETE, OP_YANK, OP_CHANGE)
; Handles: get_count, check_cursor_in_line, batch check (OP_DELETE only),
;          range computation, apply_char_operator, clamp, clear_count.
; OP_CHANGE bails into insert mode on empty line or failed range.
word_op_forward:
  PHA                          ; Save operator
  JSR get_count                ; BUF_TEMP16 = N
  JSR check_cursor_in_line
  BCS .bail

  CP16 CURSOR_COL16, RENDER_FROM_COL16

  ; Check for batched delete (OP_DELETE with BATCH_EXTRA > 0)
  TSX
  LDA $0101,X                  ; Peek operator from stack
  CMP #OP_DELETE
  BNE .non_batched
  LDA BATCH_EXTRA
  BNE .batched

.non_batched:
  LDX BUF_TEMP16
  JSR .call_range              ; BUF_LEN16 = range
  BCS .bail
  PLA                          ; A = operator
  CMP #OP_CHANGE
  PHA                          ; Re-save (A preserved, flags from CMP)
  BEQ .do_change
  ; OP_DELETE or OP_YANK
  JSR apply_char_operator
  PLA
  JSR clamp_cursor_col
  JMP clear_count

.do_change:
  PLA                          ; A = OP_CHANGE
  JSR apply_char_operator      ; Enters insert mode + clear_count
  RTS

.batched:
  PLA                          ; Discard operator (always DELETE)
  JSR batched_word_delete_fwd
  JSR clamp_cursor_col
  JMP clear_count

.bail:
  PLA                          ; Recover operator
  CMP #OP_CHANGE
  BEQ .bail_insert
  JMP clear_count

.bail_insert:
  JMP enter_insert_mode_render

.call_range:
  JMP (JUMP_TARGET16)

; Backward word operation: handles delete, yank, and change for b motion.
; Input: A = operator (OP_DELETE, OP_YANK, OP_CHANGE)
; Uses compute_multiline_word_range_backward directly.
; Handles: get_count, file-start bail, batch check (OP_DELETE only),
;          range computation, apply_char_operator, clamp, clear_count.
; OP_CHANGE bails into insert mode at file start or failed range.
word_op_backward:
  PHA                          ; Save operator
  JSR get_count                ; BUF_TEMP16 = N
  ; Bail at file start (col 0 AND line 0)
  TST16 CURSOR_COL16
  BNE .ok
  TST16 FILE_LINE16
  BEQ .bail
.ok:
  ; Check for batched delete (OP_DELETE with BATCH_EXTRA > 0)
  TSX
  LDA $0101,X                  ; Peek operator from stack
  CMP #OP_DELETE
  BNE .non_batched
  LDA BATCH_EXTRA
  BNE .batched

.non_batched:
  LDX BUF_TEMP16
  JSR compute_multiline_word_range_backward
  BCS .bail
  CP16 CURSOR_COL16, RENDER_FROM_COL16
  PLA                          ; A = operator
  CMP #OP_CHANGE
  PHA                          ; Re-save (A preserved, flags from CMP)
  BEQ .do_change
  ; OP_DELETE or OP_YANK
  JSR apply_char_operator
  PLA
  JSR clamp_cursor_col
  JMP clear_count

.do_change:
  PLA                          ; A = OP_CHANGE
  JSR apply_char_operator      ; Enters insert mode + clear_count
  RTS

.batched:
  PLA                          ; Discard operator (always DELETE)
  JSR batched_word_delete_bwd
  JSR clamp_cursor_col
  JMP clear_count

.bail:
  PLA                          ; Recover operator
  CMP #OP_CHANGE
  BEQ .bail_insert
  JMP clear_count

.bail_insert:
  JMP enter_insert_mode_render

; --- Batched word delete helpers ---

; Batched word delete forward (shared by dw and de batched paths)
; Input: JUMP_TARGET16 = range computation function pointer
;        BUF_TEMP16 = N (total word count, >= 2)
; Computes full N-word range, yanks last word only, deletes all in single shift.
; Clobbers: A, X, Y, BUF_PTR16, BUF_SRC16, BUF_DST16, BUF_LEN16, BUF_TEMP16,
;           NORMAL_TEMP, WORD_CLASS, LINE_LEN16
batched_word_delete_fwd:
  ; Save N on stack
  LDA BUF_TEMP16
  PHA

  ; Compute full N-word range
  LDX BUF_TEMP16
  JSR .fwd_call_range          ; BUF_LEN16 = full_range, cursor restored
  BCS .fwd_bail

  ; Save full_range on stack
  PUSH16 BUF_LEN16

  ; Compute (N-1)-word prefix range
  TSX
  LDA $0103,X                  ; Recover N (under 2 bytes of full_range)
  SEC
  SBC #1
  TAX                           ; X = N-1
  JSR .fwd_call_range          ; BUF_LEN16 = prefix_range, cursor restored

  ; Yank last word using buffer pointer arithmetic (no cursor movement)
  ; BUF_LEN16 = prefix_range
  JSR yank_clear
  JSR get_cursor_buf_ptr        ; BUF_PTR16 = cursor buf address

  ; BUF_SRC16 = cursor_buf_ptr + prefix_range = start of last word
  CLC
  ADC16 BUF_PTR16, BUF_LEN16, BUF_SRC16

  ; Recover full_range, discard N
  POP16 BUF_TEMP16              ; BUF_TEMP16 = full_range
  PLA                           ; discard N

  ; last_word_len = full_range - prefix_range
  SEC
  SBC16 BUF_TEMP16, BUF_LEN16, BUF_LEN16  ; BUF_LEN16 = last_word_len

  ; Yank the last word
  JSR yank_add_chars            ; Yank BUF_LEN16 chars from BUF_SRC16

  ; Delete full range at cursor (single shift)
  CP16 BUF_TEMP16, BUF_LEN16   ; BUF_LEN16 = full_range
  JSR delete_at_cursor

  RTS

.fwd_bail:
  PLA                           ; Clean up N
  RTS

.fwd_call_range:
  JMP (JUMP_TARGET16)

; Batched word delete backward (for db batched path)
; Input: BUF_TEMP16 = N (total word count, >= 2)
; Computes full N-word backward range, yanks last word only, deletes all in single shift.
; Clobbers: A, X, Y, BUF_PTR16, BUF_SRC16, BUF_DST16, BUF_LEN16, BUF_TEMP16,
;           NORMAL_TEMP, WORD_CLASS, LINE_LEN16, COUNT16, BATCH_EXTRA
batched_word_delete_bwd:
  ; Save original position on stack
  PUSH16 CURSOR_COL16
  PUSH16 FILE_LINE16

  ; Save N in BATCH_EXTRA (safe across backward range computation)
  LDA BUF_TEMP16
  STA BATCH_EXTRA

  ; Compute N-word backward range
  LDX BUF_TEMP16
  JSR compute_multiline_word_range_backward  ; cursor -> S, BUF_LEN16 = full_range
  BCS .bwd_bail

  ; Save S position and full_range in zero-page temps (safe across backward range)
  CP16 CURSOR_COL16, BUF_TEMP16 ; BUF_TEMP16 = S col
  CP16 FILE_LINE16, BUF_DST16   ; BUF_DST16 = S line
  CP16 BUF_LEN16, COUNT16       ; COUNT16 = full_range

  ; Restore original position for (N-1) computation
  POP16 FILE_LINE16
  POP16 CURSOR_COL16

  ; Compute (N-1)-word backward range
  LDA BATCH_EXTRA
  SEC
  SBC #1
  TAX                            ; X = N-1
  JSR compute_multiline_word_range_backward  ; cursor -> M, BUF_LEN16 = prefix_range

  ; Restore S position (for yank and delete)
  CP16 BUF_TEMP16, CURSOR_COL16 ; Restore S col
  CP16 BUF_DST16, FILE_LINE16   ; Restore S line
  CP16 CURSOR_COL16, RENDER_FROM_COL16

  ; Compute last_word_range = full_range - prefix_range
  SEC
  SBC16 COUNT16, BUF_LEN16, BUF_LEN16  ; BUF_LEN16 = last_word_range

  ; Yank last word at S
  JSR yank_clear
  JSR get_cursor_buf_ptr         ; BUF_PTR16 = buffer address at S
  CP16 BUF_PTR16, BUF_SRC16     ; BUF_SRC16 = yank source
  JSR yank_add_chars             ; Yank last_word_range chars

  ; Delete full range at S (single shift)
  CP16 COUNT16, BUF_LEN16       ; BUF_LEN16 = full_range
  JSR delete_at_cursor

  RTS

.bwd_bail:
  POP16 FILE_LINE16
  POP16 CURSOR_COL16
  RTS
