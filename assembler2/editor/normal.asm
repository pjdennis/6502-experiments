; Normal mode command handlers

  .zeropage

LAST_KEY:       .byte  ; Previous key for multi-key commands (dd, gg, yy, m, ')
LINE_LEN16:     .word  ; Cached length of current line (16-bit)
DISPATCH_PTR16: .word  ; Pointer into dispatch table during scan
JUMP_TARGET16:  .word  ; Target for indirect jump
COUNT16:        .word  ; Accumulated count (0 = no count entered)
COUNT_ACTIVE:   .byte  ; $FF if digits are being entered, $00 otherwise
NORMAL_TEMP:    .byte  ; Temp byte for normal mode operations

  .code

; Initialize normal mode state
normal_init:
  LDA #0
  STA LAST_KEY
  STA_LH16 COUNT16
  STA COUNT_ACTIVE
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
.exec_dd:
  JMP do_dd
.exec_gg:
  JMP do_gg
.exec_yy:
  JMP do_yy
.exec_cc:
  JMP do_cc
.exec_indent:
  JMP do_indent
.exec_unindent:
  JMP do_unindent
.exec_dw:
  JMP do_dw
.exec_db:
  JMP do_db
.exec_cw:
  JMP do_cw
.exec_cb:
  JMP do_cb
.exec_mark_set:
  JMP do_mark_set
.exec_mark_goto:
  JMP do_mark_goto
.exec_replace:
  JMP do_replace_char

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
  .byte 'n'         .word normal_find_next
  .byte 'N'         .word normal_find_prev
  .byte 'w'         .word normal_word_forward
  .byte 'b'         .word normal_word_backward
  .byte 'e'         .word normal_word_end
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

; --- Generic key dispatcher ---
; Input: A = low byte, X = high byte of dispatch table address
;        BUF_TEMP = key code to match
; Output: C = 0 if handler was called, C = 1 if no match
dispatch_key:
  STA DISPATCH_PTR16
  STX DISPATCH_PTR16 + 1
  LDY #0
.loop:
  LDA (DISPATCH_PTR16),Y
  BEQ .no_match
  CMP BUF_TEMP
  BEQ .found
  INY
  INY
  INY
  JMP .loop
.found:
  INY
  LDA (DISPATCH_PTR16),Y
  STA JUMP_TARGET16
  INY
  LDA (DISPATCH_PTR16),Y
  STA JUMP_TARGET16 + 1
  JSR .do_jump
  CLC
  RTS
.no_match:
  SEC
  RTS
.do_jump:
  JMP (JUMP_TARGET16)

; --- Movement ---

normal_move_left:
  JSR get_count          ; BUF_TEMP16 = count
  LDX BUF_TEMP16         ; X = count (low byte, capped at 255)
.left_loop:
  TST16 CURSOR_COL16
  BEQ .left_done
  LDA #0
  STA RENDER_FLAG
  DEC16 CURSOR_COL16
  DEX
  BNE .left_loop
.left_done:
  JSR ensure_cursor_visible
  JMP clear_count

normal_move_right:
  JSR get_count          ; BUF_TEMP16 = count
  LDX BUF_TEMP16         ; X = count (low byte, capped at 255)
.right_loop:
  STX BUF_TEMP           ; Save counter
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .right_done        ; Empty line
  SEC
  SBCI16 LINE_LEN16, 1, LINE_LEN16  ; LINE_LEN16 = len - 1
  CMP16 LINE_LEN16, CURSOR_COL16
  BCC .right_done        ; Already at or past end
  BEQ .right_done
  LDA #0
  STA RENDER_FLAG
  INC16 CURSOR_COL16
  LDX BUF_TEMP
  DEX
  BNE .right_loop
.right_done:
  JSR ensure_cursor_visible
  JMP clear_count

normal_move_down:
  JSR get_count          ; BUF_TEMP16 = count
  LDX BUF_TEMP16         ; X = count (low byte, capped at 255)
  STX BUF_DELTA
  JSR count_pending_key  ; X = pending matching keys
  TXA
  CLC
  ADC BUF_DELTA          ; Total = count + pending
  BCS .cap_down          ; Overflow -> cap at 255
  TAX
  JMP .down_loop
.cap_down:
  LDX #$FF
.down_loop:
  STX BUF_TEMP           ; Save counter
  ; Check if there's a next line
  CLC
  ADCI16 FILE_LINE16, 1, BUF_PTR16
  CMP16 BUF_PTR16, LINE_COUNT16
  BCS .down_done

  LDA #0
  STA RENDER_FLAG
  INC16 FILE_LINE16
  LDX BUF_TEMP
  DEX
  BNE .down_loop
.down_done:
  JSR clamp_cursor_col
  JSR ensure_cursor_visible
  JMP clear_count

normal_move_up:
  JSR get_count          ; BUF_TEMP16 = count
  LDX BUF_TEMP16         ; X = count (low byte, capped at 255)
  STX BUF_DELTA
  JSR count_pending_key  ; X = pending matching keys
  TXA
  CLC
  ADC BUF_DELTA          ; Total = count + pending
  BCS .cap_up            ; Overflow -> cap at 255
  TAX
  JMP .up_loop
.cap_up:
  LDX #$FF
.up_loop:
  STX BUF_TEMP           ; Save counter
  TST16 FILE_LINE16
  BEQ .up_done

  LDA #0
  STA RENDER_FLAG
  DEC16 FILE_LINE16
  LDX BUF_TEMP
  DEX
  BNE .up_loop
.up_done:
  JSR clamp_cursor_col
  JSR ensure_cursor_visible
  JMP clear_count

normal_page_down:
  ; page_size = SCREEN_ROWS - 1 (content rows excluding status bar)
  LDA SCREEN_ROWS
  SEC
  SBC #1
  STA BUF_TEMP       ; BUF_TEMP = page_size

  ; target_line = FILE_LINE16 + page_size, clamped to LINE_COUNT16 - 1
  CLC
  LDA FILE_LINE16
  ADC BUF_TEMP
  STA BUF_PTR16
  LDA FILE_LINE16 + 1
  ADC #0
  STA BUF_PTR16 + 1

  ; Clamp target to LINE_COUNT16 - 1
  CMP16 BUF_PTR16, LINE_COUNT16
  BCC .target_ok
.clamp_target:
  SEC
  SBCI16 LINE_COUNT16, 1, BUF_PTR16
.target_ok:

  ; VIEW_TOP16 += page_size
  CLC
  LDA VIEW_TOP16
  ADC BUF_TEMP
  STA VIEW_TOP16
  LDA VIEW_TOP16 + 1
  ADC #0
  STA VIEW_TOP16 + 1

  ; Clamp VIEW_TOP16 to max(0, LINE_COUNT - page_size)
  SEC
  LDA LINE_COUNT16
  SBC BUF_TEMP
  TAX                ; X = low byte of max view top
  LDA LINE_COUNT16 + 1
  SBC #0
  BCC .view_zero  ; LINE_COUNT < page_size, set VIEW_TOP=0
  TAY                ; Y = high byte of max view top

  ; If VIEW_TOP16 > max, clamp it
  CPY VIEW_TOP16 + 1
  BCC .clamp_view
  BNE .set_row
  CPX VIEW_TOP16
  BCS .set_row
.clamp_view:
  STX VIEW_TOP16
  STY VIEW_TOP16 + 1
  JMP .set_row

.view_zero:
  LDA #0
  STA_LH16 VIEW_TOP16

.set_row:
  CP16 BUF_PTR16, FILE_LINE16
  LDA #0
  STA_LH16 CURSOR_COL16
  STA VIEW_TOP_WRAP
  JSR ensure_cursor_visible
  JSR clamp_cursor_col
  JMP clear_count

normal_page_up:
  ; page_size = SCREEN_ROWS - 1
  LDA SCREEN_ROWS
  SEC
  SBC #1
  STA BUF_TEMP       ; BUF_TEMP = page_size

  ; target_line = FILE_LINE16 - page_size, clamped to 0
  SEC
  LDA FILE_LINE16
  SBC BUF_TEMP
  STA BUF_PTR16
  LDA FILE_LINE16 + 1
  SBC #0
  STA BUF_PTR16 + 1
  BCS .target_ok
  ; Underflow - clamp to 0
  LDA #0
  STA_LH16 BUF_PTR16
.target_ok:

  ; VIEW_TOP16 -= page_size, clamped to 0
  LDA VIEW_TOP16 + 1
  BNE .can_sub  ; High byte > 0, definitely >= page_size
  LDA VIEW_TOP16
  CMP BUF_TEMP
  BCS .can_sub

  ; VIEW_TOP16 < page_size: set VIEW_TOP16 = 0
  LDA #0
  STA_LH16 VIEW_TOP16
  JMP .set_row

.can_sub:
  SEC
  LDA VIEW_TOP16
  SBC BUF_TEMP
  STA VIEW_TOP16
  LDA VIEW_TOP16 + 1
  SBC #0
  STA VIEW_TOP16 + 1

.set_row:
  CP16 BUF_PTR16, FILE_LINE16
  LDA #0
  STA_LH16 CURSOR_COL16
  STA VIEW_TOP_WRAP
  JSR ensure_cursor_visible
  JSR clamp_cursor_col
  JMP clear_count

normal_line_start:
  LDA #0
  STA_LH16 CURSOR_COL16
  STA RENDER_FLAG
  JSR ensure_cursor_visible
  JMP clear_count

normal_line_end:
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .empty
  SEC
  SBCI16 LINE_LEN16, 1, CURSOR_COL16
  JMP .ecv
.empty:
  LDA #0
  STA_LH16 CURSOR_COL16
.ecv:
  LDA #0
  STA RENDER_FLAG
  JSR ensure_cursor_visible
  JMP clear_count

normal_goto_last:
  ; If count is set, go to line N (1-based)
  TST16 COUNT16
  BEQ .goto_end

  ; Convert 1-based count to 0-based file line
  SEC
  SBCI16 COUNT16, 1, FILE_LINE16

  ; Clamp to last line
  CMP16 FILE_LINE16, LINE_COUNT16
  BCC .goto_set
  SEC
  SBCI16 LINE_COUNT16, 1, FILE_LINE16
  JMP .goto_set

.goto_end:
  ; No count: go to last line
  SEC
  SBCI16 LINE_COUNT16, 1, FILE_LINE16

.goto_set:
  LDA #0
  STA_LH16 CURSOR_COL16
  STA VIEW_TOP_WRAP
  JSR ensure_cursor_visible
  JSR clamp_cursor_col
  JMP clear_count

normal_g_key:
  LDA #'g'
  JMP set_pending_key

; gg: go to top of file
do_gg:
  LDA #0
  STA_LH16 FILE_LINE16
  STA_LH16 VIEW_TOP16
  STA CURSOR_ROW
  STA_LH16 CURSOR_COL16
  STA VIEW_TOP_WRAP
  JSR clamp_cursor_col
  JMP clear_count

; --- Editing ---

normal_delete_char:
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BNE .not_empty
  JMP .done
.not_empty:

  CMP16 CURSOR_COL16, LINE_LEN16
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

  LDA #1
  STA RENDER_FLAG
  LDA #$FF
  STA MODIFIED
  JSR clamp_cursor_col
.done:
  JMP clear_count

normal_delete_to_eol:
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .done
  CMP16 CURSOR_COL16, LINE_LEN16
  BCS .done                ; Cursor at or past end

  ; count = LINE_LEN16 - CURSOR_COL16 (16-bit)
  SEC
  SBC16 LINE_LEN16, CURSOR_COL16, BUF_LEN16

  ; Yank deleted chars before deleting
  JSR get_cursor_buf_ptr     ; BUF_PTR16 = cursor position
  CP16 BUF_PTR16, BUF_SRC16 ; BUF_SRC16 = source for yank
  JSR yank_add_chars         ; Ignore failure; clobbers BUF_LEN16, BUF_PTR16

  ; Recompute count and cursor pointer
  SEC
  SBC16 LINE_LEN16, CURSOR_COL16, BUF_LEN16
  JSR get_cursor_buf_ptr

  ; Delete BUF_LEN16 chars at cursor position
  JSR buf_shift_left_16
  JSR buf_rebuild_lines

  LDA #$FF
  STA MODIFIED
  JSR clamp_cursor_col
.done:
  JMP clear_count

normal_d_key:
  LDA #'d'
  JMP set_pending_key

; dd: yank then delete N lines (N = count, min 1)
do_dd:
  JSR yank_clear
  JSR get_count              ; BUF_TEMP16 = count (16-bit)
  LDAX16 FILE_LINE16
  JSR yank_add_lines
  BCS .yank_overflow

  ; Adjust marks before deletion
  LDAX16 FILE_LINE16
  JSR mark_adjust_delete

  ; Delete all N lines in one batch operation
  LDAX16 FILE_LINE16
  JSR buf_delete_lines

  ; Clamp file line if past end of file
  CMP16 FILE_LINE16, LINE_COUNT16
  BCC .done
  SEC
  SBCI16 LINE_COUNT16, 1, FILE_LINE16

.done:
  LDA #$FF
  STA MODIFIED
  JSR clamp_cursor_col
  JMP clear_count

.yank_overflow:
  ; Yank buffer full - clear yank, show error, don't delete
  JSR yank_clear
  SET16 str_yank_full, STR_PTR16
  JSR show_status_message
  JMP clear_count

normal_enter_insert:
  LDA #MODE_INSERT
  STA MODE
  JMP clear_count

normal_enter_insert_after:
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

; Adjust marks after paste: total lines = YANK_LINES16 * NORMAL_TEMP (16-bit)
; Sets MODIFIED flag
paste_adjust_marks:
  ; BUF_TEMP16 = YANK_LINES16 * NORMAL_TEMP (16-bit multiplication)
  ; Start with YANK_LINES16 as base
  CP16 YANK_LINES16, BUF_TEMP16

  ; Check if paste count is 1
  LDA NORMAL_TEMP
  CMP #1
  BEQ .adjust

  ; Decrement count (already have one copy in BUF_TEMP16)
  DEC NORMAL_TEMP

.mul:
  ; BUF_TEMP16 += YANK_LINES16
  CLC
  ADC16 BUF_TEMP16, YANK_LINES16, BUF_TEMP16
  DEC NORMAL_TEMP
  BNE .mul

.adjust:
  LDAX16 FILE_LINE16
  JSR mark_adjust_insert
  LDA #$FF
  STA MODIFIED
  RTS

; Check if count (X) pastes of BUF_LEN16 bytes fit in the text buffer
; Call after yank_get_size (which sets BUF_LEN16)
; Returns carry clear = fits, carry set = doesn't fit
; Clobbers A, X, BUF_SRC16
check_paste_fits:
  ; available = BUF_LIMIT:00 - BUF_END16
  LDA #0
  SEC
  SBC BUF_END16
  STA BUF_SRC16
  LDA BUF_LIMIT
  SBC BUF_END16 + 1
  STA BUF_SRC16 + 1
  ; Subtract BUF_LEN16 from available, count times
.loop:
  SEC
  LDA BUF_SRC16
  SBC BUF_LEN16
  STA BUF_SRC16
  LDA BUF_SRC16 + 1
  SBC BUF_LEN16 + 1
  BCC .no_room
  STA BUF_SRC16 + 1
  DEX
  BNE .loop
  CLC
  RTS
.no_room:
  SEC
  RTS

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

normal_y_key:
  LDA #'y'
  JMP set_pending_key

; yy: yank N lines starting at current line
do_yy:
  JSR yank_clear
  JSR get_count              ; BUF_TEMP16 = count (16-bit)
  LDAX16 FILE_LINE16
  JSR yank_add_lines
  BCS .overflow
  JMP clear_count            ; Done - don't set MODIFIED

.overflow:
  JSR yank_clear
  SET16 str_yank_full, STR_PTR16
  JSR show_status_message
  JMP clear_count

normal_search:
  JSR search_handle
  JMP clear_count

normal_find_next:
  LDA SEARCH_LEN
  BEQ .none        ; No search pattern
  JSR search_forward
  JMP clear_count
.none:
  ; No prior search, just cursor-only update
  LDA #0
  STA RENDER_FLAG
  JMP clear_count

normal_find_prev:
  LDA SEARCH_LEN
  BEQ .none        ; No search pattern
  JSR search_backward
  JMP clear_count
.none:
  ; No prior search, just cursor-only update
  LDA #0
  STA RENDER_FLAG
  JMP clear_count

normal_mark_set:
  LDA #'m'
  JMP set_pending_key

normal_mark_goto:
  LDA #'\''
  JMP set_pending_key

; Execute mark set with register letter in BUF_TEMP
do_mark_set:
  LDA BUF_TEMP
  JSR mark_set
  LDA #0
  STA RENDER_FLAG
  JMP clear_count

; Execute mark goto with register letter in BUF_TEMP
do_mark_goto:
  LDA BUF_TEMP
  JSR mark_get
  BCS .mark_not_set
  STAX16 FILE_LINE16
  LDA #0
  STA_LH16 CURSOR_COL16
  JSR ensure_cursor_visible
  JSR clamp_cursor_col
  JMP clear_count
.mark_not_set:
  SET16 str_mark_not_set, STR_PTR16
  JSR show_status_message
  JMP clear_count

normal_enter_command:
  LDA #MODE_COMMAND
  STA MODE
  JMP clear_count

; --- Toggle case (~) ---
normal_toggle_case:
  JSR get_count
  LDX BUF_TEMP16

.tilde_loop:
  STX NORMAL_TEMP
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .tilde_done
  CMP16 CURSOR_COL16, LINE_LEN16
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
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .sub_insert
  CMP16 CURSOR_COL16, LINE_LEN16
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
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .c_insert
  CMP16 CURSOR_COL16, LINE_LEN16
  BCS .c_insert

  SEC
  SBC16 LINE_LEN16, CURSOR_COL16, BUF_LEN16

  JSR get_cursor_buf_ptr
  CP16 BUF_PTR16, BUF_SRC16
  JSR yank_add_chars

  SEC
  SBC16 LINE_LEN16, CURSOR_COL16, BUF_LEN16
  JSR get_cursor_buf_ptr
  JSR buf_shift_left_16
  JSR buf_rebuild_lines

  LDA #$FF
  STA MODIFIED

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
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .replace_done
  CMP16 CURSOR_COL16, LINE_LEN16
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
  JSR yank_clear
  LDAX16 FILE_LINE16
  JSR yank_add_lines
  BCS .cc_overflow

  LDAX16 FILE_LINE16
  JSR mark_adjust_delete

  LDAX16 FILE_LINE16
  JSR buf_delete_lines

  ; Clamp file line if past end
  CMP16 FILE_LINE16, LINE_COUNT16
  BCC .cc_insert_nl
  SEC
  SBCI16 LINE_COUNT16, 1, FILE_LINE16

.cc_insert_nl:
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
  JSR yank_clear
  SET16 str_yank_full, STR_PTR16
  JSR show_status_message
  JMP clear_count

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
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BNE .dw_not_empty
  JMP .dw_done
.dw_not_empty:
  CMP16 CURSOR_COL16, LINE_LEN16
  BCC .dw_in_range
  JMP .dw_done
.dw_in_range:

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
.dw_skip_same:
  INC16 BUF_LEN16
  CMP16 BUF_LEN16, LINE_LEN16
  BCS .dw_have_end
  JSR get_scan_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP WORD_CLASS
  BEQ .dw_skip_same
  CMP #0
  BNE .dw_have_end

  ; Skip trailing whitespace
.dw_skip_ws:
  INC16 BUF_LEN16
  CMP16 BUF_LEN16, LINE_LEN16
  BCS .dw_have_end
  JSR get_scan_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP #0
  BEQ .dw_skip_ws

.dw_have_end:
  ; delete count = BUF_LEN16 - CURSOR_COL16
  SEC
  SBC16 BUF_LEN16, CURSOR_COL16, BUF_LEN16
  PUSH16 BUF_LEN16           ; Save delete count

  ; Yank
  JSR get_cursor_buf_ptr
  CP16 BUF_PTR16, BUF_SRC16
  JSR yank_add_chars

  ; Delete (restore count, recompute pointer)
  POP16 BUF_LEN16
  JSR get_cursor_buf_ptr
  JSR buf_shift_left_16
  JSR buf_rebuild_lines
  LDA #$FF
  STA MODIFIED

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

  ; Find backward word boundary starting from CURSOR_COL16 - 1
  SEC
  SBCI16 CURSOR_COL16, 1, BUF_LEN16

  ; Skip whitespace backward
.db_skip_ws:
  JSR get_scan_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP #0
  BNE .db_found_nonws
  TST16 BUF_LEN16
  BEQ .db_have_start
  DEC16 BUF_LEN16
  JMP .db_skip_ws

.db_found_nonws:
  STA WORD_CLASS

  ; Skip same-class chars backward
.db_skip_same:
  TST16 BUF_LEN16
  BEQ .db_have_start
  DEC16 BUF_LEN16
  JSR get_scan_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP WORD_CLASS
  BEQ .db_skip_same
  INC16 BUF_LEN16           ; Different class - word starts one to right

.db_have_start:
  ; BUF_LEN16 = start position. Delete from start to cursor.
  ; Yank: source = line_ptr + start, count = cursor - start
  PUSH16 BUF_LEN16           ; Save start position
  JSR get_scan_buf_ptr        ; BUF_PTR16 = line + start_pos
  CP16 BUF_PTR16, BUF_SRC16
  SEC
  SBC16 CURSOR_COL16, BUF_LEN16, BUF_LEN16   ; BUF_LEN16 = delete count
  PUSH16 BUF_LEN16           ; Save delete count
  JSR yank_add_chars

  ; Delete: restore count and start position
  POP16 BUF_LEN16            ; delete count
  POP16 CURSOR_COL16         ; move cursor to start position
  JSR get_cursor_buf_ptr
  JSR buf_shift_left_16
  JSR buf_rebuild_lines
  LDA #$FF
  STA MODIFIED

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
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BNE .cw_not_empty
  JMP .cw_insert
.cw_not_empty:
  CMP16 CURSOR_COL16, LINE_LEN16
  BCC .cw_in_range
  JMP .cw_insert
.cw_in_range:

  ; Find end of current word (no trailing whitespace)
  CP16 CURSOR_COL16, BUF_LEN16
  JSR get_cursor_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  STA WORD_CLASS
  CMP #0
  BEQ .cw_skip_ws_first

  ; Skip same-class chars
.cw_skip_same:
  INC16 BUF_LEN16
  CMP16 BUF_LEN16, LINE_LEN16
  BCS .cw_have_end
  JSR get_scan_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP WORD_CLASS
  BEQ .cw_skip_same
  JMP .cw_have_end

.cw_skip_ws_first:
  ; On whitespace: skip ws, then skip that word class
  INC16 BUF_LEN16
  CMP16 BUF_LEN16, LINE_LEN16
  BCS .cw_have_end
  JSR get_scan_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP #0
  BEQ .cw_skip_ws_first
  STA WORD_CLASS
  JMP .cw_skip_same

.cw_have_end:
  ; delete count = BUF_LEN16 - CURSOR_COL16
  SEC
  SBC16 BUF_LEN16, CURSOR_COL16, BUF_LEN16
  PUSH16 BUF_LEN16           ; Save delete count

  ; Yank
  JSR get_cursor_buf_ptr
  CP16 BUF_PTR16, BUF_SRC16
  JSR yank_add_chars

  ; Delete (restore count, recompute pointer)
  POP16 BUF_LEN16
  JSR get_cursor_buf_ptr
  JSR buf_shift_left_16
  JSR buf_rebuild_lines
  LDA #$FF
  STA MODIFIED

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

  ; Find backward word boundary (same as db)
  SEC
  SBCI16 CURSOR_COL16, 1, BUF_LEN16

.cb_skip_ws:
  JSR get_scan_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP #0
  BNE .cb_found_nonws
  TST16 BUF_LEN16
  BEQ .cb_have_start
  DEC16 BUF_LEN16
  JMP .cb_skip_ws

.cb_found_nonws:
  STA WORD_CLASS

.cb_skip_same:
  TST16 BUF_LEN16
  BEQ .cb_have_start
  DEC16 BUF_LEN16
  JSR get_scan_buf_ptr
  LDY #0
  LDA (BUF_PTR16),Y
  JSR char_class
  CMP WORD_CLASS
  BEQ .cb_skip_same
  INC16 BUF_LEN16

.cb_have_start:
  ; Yank from start to cursor
  PUSH16 BUF_LEN16
  JSR get_scan_buf_ptr
  CP16 BUF_PTR16, BUF_SRC16
  SEC
  SBC16 CURSOR_COL16, BUF_LEN16, BUF_LEN16
  PUSH16 BUF_LEN16
  JSR yank_add_chars

  ; Delete
  POP16 BUF_LEN16
  POP16 CURSOR_COL16
  JSR get_cursor_buf_ptr
  JSR buf_shift_left_16
  JSR buf_rebuild_lines
  LDA #$FF
  STA MODIFIED

  LDX NORMAL_TEMP
  DEX
  BEQ .cb_insert
  JMP .cb_loop

.cb_insert:
  LDA #MODE_INSERT
  STA MODE
  JMP clear_count

; --- Utilities ---

get_current_line_len:
  LDAX16 FILE_LINE16
  JMP buf_get_line_len

; Get buffer pointer at cursor position on current line
; Sets BUF_PTR16 to start of FILE_LINE16 + CURSOR_COL16
; Clobbers A, X, Y
get_cursor_buf_ptr:
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr
  CLC
  ADC16 CURSOR_COL16, BUF_PTR16, BUF_PTR16
  RTS

; Get buffer pointer at BUF_LEN16 offset on current line
; Sets BUF_PTR16 = start of FILE_LINE16 + BUF_LEN16
; Clobbers A, X, Y
get_scan_buf_ptr:
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr
  CLC
  ADC16 BUF_LEN16, BUF_PTR16, BUF_PTR16
  RTS

clamp_cursor_col:
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .set_zero
  SEC
  SBCI16 LINE_LEN16, 1, LINE_LEN16  ; LINE_LEN16 = len - 1
  CMP16 LINE_LEN16, CURSOR_COL16
  BCS .ok                ; len-1 >= cursor, cursor is fine
  CP16 LINE_LEN16, CURSOR_COL16
.ok:
  RTS
.set_zero:
  LDA #0
  STA_LH16 CURSOR_COL16
  RTS

; --- Count prefix helpers ---

; Set pending key for multi-key commands (dd, gg, yy, m, ')
; A = key character to store
set_pending_key:
  STA LAST_KEY
  LDA #0
  STA RENDER_FLAG
  RTS

; Clear count state: zeroes COUNT16, COUNT_ACTIVE, LAST_KEY
clear_count:
  LDA #0
  STA_LH16 COUNT16
  STA COUNT_ACTIVE
  STA LAST_KEY
  RTS

; Accumulate digit in A ('0'-'9') into COUNT16
; COUNT16 = COUNT16 * 10 + digit
; If COUNT16 >= 1000, digit is ignored (prevents overflow)
; Clobbers A
count_accumulate_digit:
  ; Check if count already >= 1000 ($03E8)
  PHA                    ; Save digit char
  LDA COUNT16 + 1
  CMP #$03
  BCC .count_has_room
  BNE .count_at_limit
  LDA COUNT16
  CMP #$E8
  BCC .count_has_room
.count_at_limit:
  PLA                    ; Discard digit
  RTS
.count_has_room:
  PLA                    ; Restore digit char
  SEC
  SBC #'0'
  PHA                    ; Save digit

  ; Multiply COUNT16 by 10: COUNT16 * 8 + COUNT16 * 2
  ; Save original in BUF_LEN16
  CP16 COUNT16, BUF_LEN16

  ; *2
  ASL16 COUNT16
  ; *4
  ASL16 COUNT16
  ; *8
  ASL16 COUNT16

  ; original * 2
  ASL16 BUF_LEN16

  ; COUNT16 = COUNT16*8 + original*2
  CLC
  ADC16 COUNT16, BUF_LEN16, COUNT16

  ; Add digit
  PLA
  CLC
  ADCA16 COUNT16, COUNT16

  RTS

; Get effective count: returns min(COUNT16, 255) in X, minimum 1
; If COUNT16 is 0, returns 1 (no count means "do once")
; Clobbers A
; Get effective count in BUF_TEMP16, minimum 1
; If COUNT16 is 0, returns 1 (no count means "do once")
; Clobbers: A
get_count:
  LDA COUNT16
  ORA COUNT16 + 1
  BNE .has_count
  ; Zero = no count, return 1
  LDA #1
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16 + 1
  RTS
.has_count:
  ; Copy COUNT16 to BUF_TEMP16
  LDA COUNT16
  STA BUF_TEMP16
  LDA COUNT16 + 1
  STA BUF_TEMP16 + 1
  RTS
