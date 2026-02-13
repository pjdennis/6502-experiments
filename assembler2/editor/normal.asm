; Normal mode - main handler, dispatch tables, and core editing commands

; Initialize normal mode state
normal_init:
  LDA #0
  STA LAST_KEY
  STA_LH16 COUNT16
  STA COUNT_ACTIVE
  STA BATCH_RESTORE_KEY
  STA BATCH_EXTRA
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
  ; Check if key starts a multi-key combo
  LDA #<pending_combo_keys
  LDX #>pending_combo_keys
  JSR check_combo_first_key
  BCC .done
  ; Unknown key - clear count and last key, cursor-only update
  JSR clear_count
  LDA #0
  STA RENDER_FLAG
.done:
  RTS

; --- Pending key dispatch ---
; Called when LAST_KEY is set and a second key arrives in BUF_TEMP.
; Uses table-based dispatch via dispatch_pending_key.
pending_key_dispatch:
  LDA #<pending_combo_keys
  LDX #>pending_combo_keys
  JSR dispatch_pending_key
  BCC .done
  ; No match - reset
  JSR clear_count
  LDA #0
  STA RENDER_FLAG
.done:
  RTS

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
  .byte 0           ; End sentinel

normal_editing_keys:
  .byte 'x'         .word normal_delete_char
  .byte KEY_DEL     .word normal_delete_char
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
  .byte 's'         .word normal_substitute_char
  .byte 'C'         .word normal_change_to_eol
  .byte 'S'         .word normal_substitute_line
  .byte 0           ; End sentinel

normal_other_keys:
  .byte ':'         .word normal_enter_command
  .byte 0           ; End sentinel

; Pending combo key table: 5-byte entries [last_key, second_key, flags, handler]
;   second_key=0: wildcard (any second key)
;   flags bit 0: call batch_pending_pairs before handler
;   flags bit 1: editing command (blocked in READONLY mode)
pending_combo_keys:
  .byte 'm', 0, $00         .word do_mark_set
  .byte '\'', 0, $00        .word do_mark_goto
  .byte 'r', 0, $02         .word do_replace_char
  .byte 'd', 'd', $03       .word do_dd
  .byte 'g', 'g', $00       .word do_gg
  .byte 'y', 'y', $00       .word do_yy
  .byte 'c', 'c', $02       .word do_cc
  .byte '>', '>', $02       .word do_indent
  .byte '<', '<', $02       .word do_unindent
  .byte 'd', 'w', $03       .word do_dw
  .byte 'd', 'b', $03       .word do_db
  .byte 'c', 'w', $02       .word do_cw
  .byte 'c', 'b', $02       .word do_cb
  .byte 0                   ; End sentinel

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

; dd: yank then delete N lines (N = count, min 1)
; When batched (BATCH_EXTRA > 0): delete (total-1) without yank, then
; yank_delete 1 line. This matches unbatched semantics where each dd
; overwrites the yank buffer, so only the last line is yanked.
do_dd:
  JSR get_count              ; BUF_TEMP16 = count (16-bit)
  LDA BATCH_EXTRA
  BEQ .do_yank_delete        ; No batching, standard path
  ; Batched: delete (total-1) lines without yank first
  SEC
  SBCI16 BUF_TEMP16, 1, BUF_TEMP16
  JSR delete_current_lines
  LDA #1
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16 + 1
.do_yank_delete:
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
  JMP enter_insert_mode

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
  JMP enter_insert_mode

normal_enter_insert_eol:
  LDA #0
  STA RENDER_FLAG
  JSR get_current_line_len
  STAX16 CURSOR_COL16
  JSR ensure_cursor_visible
  JMP enter_insert_mode

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
  LDA #$FF
  STA MODIFIED
  JMP enter_insert_mode
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
  LDA #$FF
  STA MODIFIED
  JMP enter_insert_mode
.open_above_full:
  SET16 str_buffer_full, STR_PTR16
  JSR show_status_message
  JMP clear_count

