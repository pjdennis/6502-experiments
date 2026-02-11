; Normal mode command handlers

  .zeropage

LAST_KEY:    .byte      ; Previous key for multi-key commands (dd, gg)
LINE_LEN16:  .word      ; Cached length of current line (16-bit)
DISPATCH_PTR16: .word    ; Pointer into dispatch table during scan
JUMP_TARGET16:  .word    ; Target for indirect jump
COUNT16:     .word      ; Accumulated count (0 = no count entered)
COUNT_ACTIVE: .byte     ; $FF if digits are being entered, $00 otherwise
NORMAL_TEMP: .byte      ; Temp byte for normal mode operations

  .code

; Initialize normal mode state
normal_init:
  LDA #0
  STA LAST_KEY
  STA COUNT16
  STA COUNT16 + 1
  STA COUNT_ACTIVE
  RTS

; Handle a keystroke in normal mode
; Key code in A
normal_handle_key:
  STA BUF_TEMP

  ; --- Count prefix handling ---

  ; ESC always clears count
  CMP #KEY_ESC
  BNE .not_esc_count
  LDA COUNT_ACTIVE
  BEQ .not_esc_count      ; No active count, let ESC fall through
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

; --- Dispatch tables ---

normal_movement_keys:
  .byte 'h'
  .word normal_move_left
  .byte KEY_LEFT
  .word normal_move_left
  .byte 'l'
  .word normal_move_right
  .byte KEY_RIGHT
  .word normal_move_right
  .byte 'j'
  .word normal_move_down
  .byte KEY_DOWN
  .word normal_move_down
  .byte 'k'
  .word normal_move_up
  .byte KEY_UP
  .word normal_move_up
  .byte '0'
  .word normal_line_start
  .byte KEY_HOME
  .word normal_line_start
  .byte '$'
  .word normal_line_end
  .byte KEY_END
  .word normal_line_end
  .byte KEY_PGDN
  .word normal_page_down
  .byte KEY_PGUP
  .word normal_page_up
  .byte $06              ; Ctrl-F
  .word normal_page_down
  .byte $02              ; Ctrl-B
  .word normal_page_up
  .byte 'G'
  .word normal_goto_last
  .byte 'g'
  .word normal_g_key
  .byte 'y'
  .word normal_y_key
  .byte '/'
  .word normal_search
  .byte 'n'
  .word normal_find_next
  .byte 'N'
  .word normal_find_prev
  .byte 'm'
  .word normal_mark_set
  .byte '\''
  .word normal_mark_goto
  .byte 0                ; End sentinel

normal_editing_keys:
  .byte 'x'
  .word normal_delete_char
  .byte KEY_DEL
  .word normal_delete_char
  .byte 'd'
  .word normal_d_key
  .byte 'D'
  .word normal_delete_to_eol
  .byte 'i'
  .word normal_enter_insert
  .byte 'a'
  .word normal_enter_insert_after
  .byte 'A'
  .word normal_enter_insert_eol
  .byte 'o'
  .word normal_open_below
  .byte 'O'
  .word normal_open_above
  .byte 'p'
  .word normal_paste_below
  .byte 'P'
  .word normal_paste_above
  .byte 0                ; End sentinel

normal_other_keys:
  .byte ':'
  .word normal_enter_command
  .byte 0                ; End sentinel

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
  JSR get_count_byte     ; X = count
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
  JSR clear_count
  RTS

normal_move_right:
  JSR get_count_byte     ; X = count
.right_loop:
  STX BUF_TEMP           ; Save counter
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .right_done        ; Empty line
  SEC
  SBCI16 LINE_LEN16, $0001, LINE_LEN16  ; LINE_LEN16 = len - 1
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
  JSR clear_count
  RTS

normal_move_down:
  JSR get_count_byte     ; X = count
.down_loop:
  STX BUF_TEMP           ; Save counter
  ; Check if there's a next line
  CLC
  ADCI16 FILE_LINE16, $0001, BUF_PTR16
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
  JSR clear_count
  RTS

normal_move_up:
  JSR get_count_byte     ; X = count
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
  JSR clear_count
  RTS

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
  SBCI16 LINE_COUNT16, $0001, BUF_PTR16
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
  SBCI16 LINE_LEN16, $0001, CURSOR_COL16
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
  SBCI16 COUNT16, $0001, FILE_LINE16

  ; Clamp to last line
  CMP16 FILE_LINE16, LINE_COUNT16
  BCC .goto_set
  SEC
  SBCI16 LINE_COUNT16, $0001, FILE_LINE16
  JMP .goto_set

.goto_end:
  ; No count: go to last line
  SEC
  SBCI16 LINE_COUNT16, $0001, FILE_LINE16

.goto_set:
  LDA #0
  STA_LH16 CURSOR_COL16
  STA VIEW_TOP_WRAP
  JSR ensure_cursor_visible
  JSR clamp_cursor_col
  JMP clear_count

normal_g_key:
  LDA LAST_KEY
  CMP #'g'
  BNE .set_g
  ; gg: go to top
  LDA #0
  STA_LH16 FILE_LINE16
  STA_LH16 VIEW_TOP16
  STA CURSOR_ROW
  STA_LH16 CURSOR_COL16
  STA VIEW_TOP_WRAP
  JSR clamp_cursor_col
  JMP clear_count
.set_g:
  LDA #'g'
  STA LAST_KEY
  LDA #0
  STA RENDER_FLAG
  RTS

; --- Editing ---

normal_delete_char:
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .done

  CMP16 CURSOR_COL16, LINE_LEN16
  BCS .done

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
  JSR get_count_byte         ; X = count

  ; Add pending matching keys (x or Delete)
  STX BUF_DELTA              ; Save count prefix
  JSR count_pending_key      ; Returns additional count in X
  TXA
  CLC
  ADC BUF_DELTA              ; Total = count + pending
  BCS .cap_at_max          ; Overflow -> cap
  TAX

  ; Cap at max deleteable
  CPX LINE_LEN16
  BCC .cap_ok
.cap_at_max:
  LDX LINE_LEN16
.cap_ok:
  STX BUF_DELTA

  ; Delete BUF_DELTA chars at cursor position
  JSR get_cursor_buf_ptr
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

  ; Delete BUF_LEN16 chars at cursor position
  JSR get_cursor_buf_ptr
  JSR buf_shift_left_16
  JSR buf_rebuild_lines

  LDA #$FF
  STA MODIFIED
  JSR clamp_cursor_col
.done:
  JMP clear_count

normal_d_key:
  LDA LAST_KEY
  CMP #'d'
  BEQ .do_dd
  JMP .set_d
.do_dd:

  ; dd: yank then delete N lines (N = count, min 1)
  JSR yank_clear
  JSR get_count_byte         ; X = count
  STX LINE_LEN16             ; LINE_LEN16 low byte = total lines to process
  STX BUF_TEMP
  LDAX16 FILE_LINE16
  JSR yank_add_lines
  BCS .yank_overflow

  ; Adjust marks before deletion
  LDA LINE_LEN16
  STA BUF_TEMP
  LDAX16 FILE_LINE16
  JSR mark_adjust_delete

  ; Delete all N lines in one batch operation
  LDA LINE_LEN16
  STA BUF_TEMP
  LDAX16 FILE_LINE16
  JSR buf_delete_lines

  ; Clamp file line if past end of file
  CMP16 FILE_LINE16, LINE_COUNT16
  BCC .done
  SEC
  SBCI16 LINE_COUNT16, $0001, FILE_LINE16

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

.set_d:
  ; First 'd': store in LAST_KEY but preserve count
  LDA #'d'
  STA LAST_KEY
  RTS

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
  STA BUF_TEMP
  CLC
  ADCI16 FILE_LINE16, $0001, BUF_DST16
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
  STA BUF_TEMP
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
  JSR get_count_byte         ; X = count
  STX BUF_TEMP
  STX NORMAL_TEMP            ; Save paste count
  JSR yank_paste_below_n
  BCS .paste_below_done
  JSR paste_adjust_marks
.paste_below_done:
  JMP clear_count

normal_paste_above:
  JSR get_count_byte         ; X = count
  STX BUF_TEMP
  STX NORMAL_TEMP            ; Save paste count
  JSR yank_paste_above_n
  BCS .paste_above_done
  JSR paste_adjust_marks
.paste_above_done:
  JMP clear_count

; Adjust marks after paste: total lines = YANK_LINES * NORMAL_TEMP (capped at 255)
; Sets MODIFIED flag
paste_adjust_marks:
  LDA #0
  LDX NORMAL_TEMP
.mul:
  CLC
  ADC YANK_LINES
  BCS .cap
  DEX
  BNE .mul
  JMP .adjust
.cap:
  LDA #$FF
.adjust:
  STA BUF_TEMP
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

normal_y_key:
  ; Two-key command: first 'y' sets LAST_KEY, second 'y' yanks
  LDA LAST_KEY
  CMP #'y'
  BEQ .do_yy
  ; First 'y': store in LAST_KEY but preserve count
  LDA #'y'
  STA LAST_KEY
  RTS

.do_yy:
  ; Yank N lines starting at current line
  JSR yank_clear
  JSR get_count_byte         ; X = count (min 1, max 255)
  STX BUF_TEMP
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
  JSR get_key
  JSR mark_set
  LDA #0
  STA RENDER_FLAG
  JMP clear_count

normal_mark_goto:
  JSR get_key
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

; --- Utilities ---

get_current_line_len:
  LDAX16 FILE_LINE16
  JSR buf_get_line_len
  RTS

; Get buffer pointer at cursor position on current line
; Sets BUF_PTR16 to start of FILE_LINE16 + CURSOR_COL16
; Clobbers A, X, Y
get_cursor_buf_ptr:
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr
  CLC
  ADC16 CURSOR_COL16, BUF_PTR16, BUF_PTR16
  RTS

clamp_cursor_col:
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .set_zero
  SEC
  SBCI16 LINE_LEN16, $0001, LINE_LEN16  ; LINE_LEN16 = len - 1
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

; Clear count state: zeroes COUNT16, COUNT_ACTIVE, LAST_KEY
clear_count:
  LDA #0
  STA COUNT16
  STA COUNT16 + 1
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
get_count_byte:
  LDA COUNT16 + 1
  BNE .cap_255           ; High byte non-zero = > 255
  LDA COUNT16
  BEQ .return_1          ; Zero = no count, return 1
  TAX
  RTS
.cap_255:
  LDX #$FF
  RTS
.return_1:
  LDX #1
  RTS
