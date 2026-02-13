; Normal mode - main handler, dispatch tables, and core editing commands

; Initialize normal mode state
normal_init:
  LDA #0
  STA LAST_KEY
  STA_LH16 COUNT16
  STA COUNT_ACTIVE
  STA BATCH_RESTORE_KEY
  RTS

; Handle a keystroke in normal mode
; Key code in A
normal_handle_key:
  STA BUF_TEMP

  ; --- Count prefix handling ---

  ; ESC always clears count and pending key
  CMP #KEY_ESC
  BNE .not_esc_count
  LDA COUNT_ACTIVE
  ORA LAST_KEY
  BEQ .not_esc_count      ; No active count or pending key, let ESC fall through
  JSR clear_count
  LDA #0
  STA RENDER_FLAG
  RTS
.not_esc_count:

  ; If COUNT_ACTIVE, check for continued digit input
  LDA COUNT_ACTIVE
  BEQ .count_not_active

  ; COUNT_ACTIVE=true: 0-9 continues accumulation
  LDA BUF_TEMP
  CMP #'0'
  BCC .count_done_dispatch
  CMP #':' ; '9'+1
  BCS .count_done_dispatch
  ; Accumulate digit into COUNT16
  JSR count_accumulate_digit
  LDA #0
  STA RENDER_FLAG
  RTS

.count_done_dispatch:
  ; Non-digit with active count: clear COUNT_ACTIVE, fall through to dispatch
  LDA #0
  STA COUNT_ACTIVE
  JMP .dispatch_key

.count_not_active:
  ; If pending key is set, don't start a new count - dispatch directly
  LDA LAST_KEY
  BNE .dispatch_key
  ; Not counting yet: 1-9 starts a new count
  LDA BUF_TEMP
  CMP #'1'
  BCC .dispatch_key
  CMP #':'  ; '9'+1
  BCS .dispatch_key
  ; Start new count
  LDA #$FF
  STA COUNT_ACTIVE
  LDA #0
  STA COUNT16
  STA COUNT16 + 1
  LDA BUF_TEMP
  JSR count_accumulate_digit
  LDA #0
  STA RENDER_FLAG
  RTS

.dispatch_key:
  LDA LAST_KEY
  BEQ .normal_dispatch
  JMP pending_key_dispatch
.normal_dispatch:
  LDA #<normal_movement_keys
  LDX #>normal_movement_keys
  JSR dispatch_key
  BCC .done
  LDA READONLY
  BNE .skip_editing
  LDA #<normal_editing_keys
  LDX #>normal_editing_keys
  JSR dispatch_key
  BCC .done
.skip_editing:
  LDA #<normal_other_keys
  LDX #>normal_other_keys
  JSR dispatch_key
  BCC .done
  ; Unknown key - clear count and last key, cursor-only update
  JSR clear_count
  LDA #0
  STA RENDER_FLAG
.done:
  RTS

; --- Pending key dispatch ---
; Called when LAST_KEY is set and a second key arrives in BUF_TEMP.
; For d/g/y: if BUF_TEMP matches LAST_KEY, execute the two-key command.
; For m/': second key is always the register letter.
pending_key_dispatch:
  ; Check for commands that always consume second key
  LDA LAST_KEY
  CMP #'m'
  BEQ .exec_mark_set
  CMP #'\''
  BEQ .exec_mark_goto
  CMP #'r'
  BEQ .exec_replace
  ; For d/g/y: second key must match first
  LDA BUF_TEMP
  CMP LAST_KEY
  BNE .not_repeat
  LDA LAST_KEY
  CMP #'d'
  BEQ .exec_dd
  CMP #'g'
  BEQ .exec_gg
  CMP #'y'
  BEQ .exec_yy
  CMP #'c'
  BEQ .exec_cc
  CMP #'>'
  BEQ .exec_indent
  CMP #'<'
  BEQ .exec_unindent
.not_repeat:
  ; Check operator+motion combos (d+w, d+b, c+w, c+b)
  LDA LAST_KEY
  CMP #'d'
  BEQ .check_d_motion
  CMP #'c'
  BEQ .check_c_motion
  ; No match - reset
  JMP .no_match

.check_d_motion:
  LDA BUF_TEMP
  CMP #'w'
  BEQ .exec_dw
  CMP #'b'
  BEQ .exec_db
  JMP .no_match

.check_c_motion:
  LDA BUF_TEMP
  CMP #'w'
  BEQ .exec_cw
  CMP #'b'
  BEQ .exec_cb
  JMP .no_match

.no_match:
  JSR clear_count
  LDA #0
  STA RENDER_FLAG
  RTS
.exec_mark_set:
  JMP do_mark_set
.exec_mark_goto:
  JMP do_mark_goto
.exec_replace:
  JMP do_replace_char
.exec_dd:
  JSR batch_pending_pairs
  JMP do_dd
.exec_gg:
  JMP do_gg
.exec_yy:
  JSR batch_pending_pairs
  JMP do_yy
.exec_cc:
  JMP do_cc
.exec_indent:
  JMP do_indent
.exec_unindent:
  JMP do_unindent
.exec_dw:
  JSR batch_pending_pairs
  JMP do_dw
.exec_db:
  JSR batch_pending_pairs
  JMP do_db
.exec_cw:
  JMP do_cw
.exec_cb:
  JMP do_cb

; --- Dispatch tables ---

normal_movement_keys:
  .byte 'h'         .word normal_move_left
  .byte KEY_LEFT    .word normal_move_left
  .byte 'l'         .word normal_move_right
  .byte KEY_RIGHT   .word normal_move_right
  .byte 'j'         .word normal_move_down
  .byte KEY_DOWN    .word normal_move_down
  .byte 'k'         .word normal_move_up
  .byte KEY_UP      .word normal_move_up
  .byte '0'         .word normal_line_start
  .byte KEY_HOME    .word normal_line_start
  .byte '$'         .word normal_line_end
  .byte KEY_END     .word normal_line_end
  .byte KEY_PGDN    .word normal_page_down
  .byte KEY_PGUP    .word normal_page_up
  .byte $06         .word normal_page_down     ; Ctrl-F
  .byte $02         .word normal_page_up       ; Ctrl-B
  .byte 'G'         .word normal_goto_last
  .byte 'g'         .word normal_g_key
  .byte 'y'         .word normal_y_key
  .byte '/'         .word normal_search
  .byte '?'         .word normal_search_backward
  .byte 'n'         .word normal_find_next
  .byte 'N'         .word normal_find_prev
  .byte 'w'         .word normal_word_forward
  .byte 'b'         .word normal_word_backward
  .byte 'e'         .word normal_word_end
  .byte KEY_WORD_FWD  .word normal_word_forward
  .byte KEY_WORD_BACK .word normal_word_backward
  .byte '^'         .word normal_first_nonblank
  .byte 'm'         .word normal_mark_set
  .byte '\''        .word normal_mark_goto
  .byte 0           ; End sentinel

normal_editing_keys:
  .byte 'x'         .word normal_delete_char
  .byte KEY_DEL     .word normal_delete_char
  .byte 'd'         .word normal_d_key
  .byte 'D'         .word normal_delete_to_eol
  .byte 'i'         .word normal_enter_insert
  .byte 'a'         .word normal_enter_insert_after
  .byte 'A'         .word normal_enter_insert_eol
  .byte 'o'         .word normal_open_below
  .byte 'O'         .word normal_open_above
  .byte 'p'         .word normal_paste_below
  .byte 'P'         .word normal_paste_above
  .byte '~'         .word normal_toggle_case
  .byte 'J'         .word normal_join_lines
  .byte 'r'         .word normal_r_key
  .byte 's'         .word normal_substitute_char
  .byte 'C'         .word normal_change_to_eol
  .byte 'S'         .word normal_substitute_line
  .byte 'c'         .word normal_c_key
  .byte '>'         .word normal_gt_key
  .byte '<'         .word normal_lt_key
  .byte 0           ; End sentinel

normal_other_keys:
  .byte ':'         .word normal_enter_command
  .byte 0           ; End sentinel

; --- Editing ---

normal_delete_char:
  JSR check_cursor_in_line
  BCC .in_range
  JMP .done
.in_range:

  ; Calculate max deleteable = LINE_LEN16 - CURSOR_COL16, capped at 255
  SEC
  SBC16 LINE_LEN16, CURSOR_COL16, LINE_LEN16
  LDA LINE_LEN16 + 1
  BNE .cap_diff            ; High byte > 0, cap at 255
  LDA LINE_LEN16
  JMP .have_max
.cap_diff:
  LDA #$FF
.have_max:
  STA LINE_LEN16            ; Reuse low byte as 8-bit cap

  ; Start with count prefix (minimum 1)
  JSR get_count              ; BUF_TEMP16 = count
  LDX BUF_TEMP16             ; X = count (low byte, capped at 255)

  ; Add pending matching keys (x or Delete)
  ; BUF_TEMP16 = yank count (last effective x command's count).
  ; Pending keys are individual x commands (count=1), so if any
  ; are batched, clamp yank count to 1.
  STX BUF_DELTA              ; Save count prefix
  JSR count_pending_key      ; Returns additional count in X
  TXA                        ; A = pending count
  BEQ .no_pending
  LDX #1
  STX BUF_TEMP16             ; Pending: last x has count=1
.no_pending:
  CLC
  ADC BUF_DELTA              ; Total = count + pending
  BCS .cap_at_max            ; Overflow -> cap
  TAX

  ; Cap at max deleteable
  CPX LINE_LEN16
  BCC .cap_ok
.cap_at_max:
  LDX LINE_LEN16
.cap_ok:
  STX BUF_DELTA

  ; Clamp yank count to delete count (e.g. 99x on short line)
  LDA BUF_TEMP16
  CMP BUF_DELTA
  BCC .yank_count_ok
  BEQ .yank_count_ok
  LDA BUF_DELTA
  STA BUF_TEMP16
.yank_count_ok:

  ; Yank BUF_TEMP16 chars from end of delete range
  JSR get_cursor_buf_ptr     ; BUF_PTR16 = cursor position
  LDA BUF_DELTA
  SEC
  SBC BUF_TEMP16             ; A = offset to yank start
  CLC
  ADCA16 BUF_PTR16, BUF_SRC16 ; BUF_SRC16 = cursor + offset
  LDA BUF_TEMP16
  STA BUF_LEN16
  LDA #0
  STA BUF_LEN16 + 1
  LDA BUF_DELTA
  PHA                        ; Save BUF_DELTA on stack
  JSR yank_add_chars         ; Ignore failure
  PLA
  STA BUF_DELTA              ; Restore BUF_DELTA

  ; Delete BUF_DELTA chars at cursor position
  JSR get_cursor_buf_ptr     ; Recompute (yank clobbered BUF_PTR16)
  JSR buf_delete_chars
  JSR buf_adjust_lines_dec

  JSR clamp_cursor_col
  LDA #1
  STA RENDER_FLAG
  JSR ensure_cursor_visible
  LDA #$FF
  STA MODIFIED
.done:
  JMP clear_count

normal_delete_to_eol:
  JSR check_cursor_in_line
  BCS .done

  ; count = LINE_LEN16 - CURSOR_COL16 (16-bit)
  SEC
  SBC16 LINE_LEN16, CURSOR_COL16, BUF_LEN16
  JSR yank_delete_at_cursor
  JSR clamp_cursor_col
  LDA #1
  STA RENDER_FLAG
  JSR ensure_cursor_visible
.done:
  JMP clear_count

normal_d_key:
  LDA #'d'
  JMP set_pending_key

; dd: yank then delete N lines (N = count, min 1)
do_dd:
  JSR get_count              ; BUF_TEMP16 = count (16-bit)
  JSR yank_delete_current_lines
  BCS .yank_overflow

  LDA #$FF
  STA MODIFIED
  JSR clamp_cursor_col
  JMP clear_count

.yank_overflow:
  JMP show_yank_overflow

normal_enter_insert:
  LDA #0
  STA RENDER_FLAG
  LDA #MODE_INSERT
  STA MODE
  JMP clear_count

normal_enter_insert_after:
  LDA #0
  STA RENDER_FLAG
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .enter
  CMP16 LINE_LEN16, CURSOR_COL16
  BEQ .enter
  BCC .enter
  INC16 CURSOR_COL16
.enter:
  JSR ensure_cursor_visible
  LDA #MODE_INSERT
  STA MODE
  JMP clear_count

normal_enter_insert_eol:
  LDA #0
  STA RENDER_FLAG
  JSR get_current_line_len
  STAX16 CURSOR_COL16
  JSR ensure_cursor_visible
  LDA #MODE_INSERT
  STA MODE
  JMP clear_count

normal_open_below:
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr

  LDY #0
.find_nl:
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .found_nl
  INY
  BNE .find_nl
  INC BUF_PTR16 + 1          ; Y wrapped: advance pointer by 256
  JMP .find_nl
.found_nl:
  INY
  BNE .no_wrap_nl
  INC BUF_PTR16 + 1          ; Y wrapped past newline: advance page
.no_wrap_nl:
  TYA
  CLC
  ADCA16 BUF_PTR16, BUF_PTR16

  LDA #'\n'
  JSR buf_insert_char
  BCS .open_below_full
  JSR buf_rebuild_lines

  ; Adjust marks: new line inserted at FILE_LINE16+1
  LDA #1
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16 + 1
  CLC
  ADCI16 FILE_LINE16, 1, BUF_DST16
  LDAX16 BUF_DST16
  JSR mark_adjust_insert

  INC16 FILE_LINE16
  LDA #0
  STA_LH16 CURSOR_COL16
  JSR ensure_cursor_visible
  LDA #MODE_INSERT
  STA MODE
  LDA #$FF
  STA MODIFIED
  JMP clear_count
.open_below_full:
  SET16 str_buffer_full, STR_PTR16
  JSR show_status_message
  JMP clear_count

normal_open_above:
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr

  LDA #'\n'
  JSR buf_insert_char
  BCS .open_above_full
  JSR buf_rebuild_lines

  ; Adjust marks: new line inserted at FILE_LINE16
  LDA #1
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16 + 1
  LDAX16 FILE_LINE16
  JSR mark_adjust_insert

  LDA #0
  STA_LH16 CURSOR_COL16
  LDA #MODE_INSERT
  STA MODE
  LDA #$FF
  STA MODIFIED
  JMP clear_count
.open_above_full:
  SET16 str_buffer_full, STR_PTR16
  JSR show_status_message
  JMP clear_count

