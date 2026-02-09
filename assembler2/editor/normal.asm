; Normal mode command handlers

  .zeropage

LAST_KEY:    .byte      ; Previous key for multi-key commands (dd, gg)
LINE_LEN:    .byte      ; Cached length of current line
DISPATCH_PTR16: .word    ; Pointer into dispatch table during scan
JUMP_TARGET16:  .word    ; Target for indirect jump

  .code

; Handle a keystroke in normal mode
; Key code in A
normal_handle_key:
  STA BUF_TEMP
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
  ; Unknown key - clear last key, cursor-only update
  LDA #0
  STA LAST_KEY
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
  .byte 0                ; End sentinel

normal_editing_keys:
  .byte 'x'
  .word normal_delete_char
  .byte KEY_DEL
  .word normal_delete_char
  .byte 'd'
  .word normal_d_key
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
  LDA CURSOR_COL
  BEQ .done
  LDA #0
  STA RENDER_FLAG
  DEC CURSOR_COL
  JSR ensure_cursor_visible
.done:
  LDA #0
  STA LAST_KEY
  RTS

normal_move_right:
  JSR get_current_line_len
  STA LINE_LEN
  BEQ .done           ; Empty line
  SEC
  SBC #1
  CMP CURSOR_COL
  BCC .done           ; Already at or past end
  BEQ .done
  LDA #0
  STA RENDER_FLAG
  INC CURSOR_COL
  JSR ensure_cursor_visible
.done:
  LDA #0
  STA LAST_KEY
  RTS

normal_move_down:
  ; Check if there's a next line
  CLC
  ADCI16 FILE_LINE16, $0001, BUF_PTR16

  CMP16 BUF_PTR16, LINE_COUNT16
  BCS .done

  LDA #0
  STA RENDER_FLAG
  INC16 FILE_LINE16
  JSR clamp_cursor_col
  JSR ensure_cursor_visible
.done:
  LDA #0
  STA LAST_KEY
  RTS

normal_move_up:
  TST16 FILE_LINE16
  BEQ .done

  LDA #0
  STA RENDER_FLAG
  DEC16 FILE_LINE16
  JSR clamp_cursor_col
  JSR ensure_cursor_visible
.done:
  LDA #0
  STA LAST_KEY
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
  BCC .pgdn_target_ok
.pgdn_clamp_target:
  SEC
  SBCI16 LINE_COUNT16, $0001, BUF_PTR16
.pgdn_target_ok:

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
  BCC .pgdn_view_zero  ; LINE_COUNT < page_size, set VIEW_TOP=0
  TAY                ; Y = high byte of max view top

  ; If VIEW_TOP16 > max, clamp it
  CPY VIEW_TOP16 + 1
  BCC .pgdn_clamp_view
  BNE .pgdn_set_row
  CPX VIEW_TOP16
  BCS .pgdn_set_row
.pgdn_clamp_view:
  STX VIEW_TOP16
  STY VIEW_TOP16 + 1
  JMP .pgdn_set_row

.pgdn_view_zero:
  LDA #0
  STA_LH16 VIEW_TOP16

.pgdn_set_row:
  CP16 BUF_PTR16, FILE_LINE16
  LDA #0
  STA CURSOR_COL
  STA VIEW_TOP_WRAP
  JSR ensure_cursor_visible
  JSR clamp_cursor_col
  LDA #0
  STA LAST_KEY
  RTS

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
  BCS .pgup_target_ok
  ; Underflow - clamp to 0
  LDA #0
  STA_LH16 BUF_PTR16
.pgup_target_ok:

  ; VIEW_TOP16 -= page_size, clamped to 0
  LDA VIEW_TOP16 + 1
  BNE .pgup_can_sub  ; High byte > 0, definitely >= page_size
  LDA VIEW_TOP16
  CMP BUF_TEMP
  BCS .pgup_can_sub

  ; VIEW_TOP16 < page_size: set VIEW_TOP16 = 0
  LDA #0
  STA_LH16 VIEW_TOP16
  JMP .pgup_set_row

.pgup_can_sub:
  SEC
  LDA VIEW_TOP16
  SBC BUF_TEMP
  STA VIEW_TOP16
  LDA VIEW_TOP16 + 1
  SBC #0
  STA VIEW_TOP16 + 1

.pgup_set_row:
  CP16 BUF_PTR16, FILE_LINE16
  LDA #0
  STA CURSOR_COL
  STA VIEW_TOP_WRAP
  JSR ensure_cursor_visible
  JSR clamp_cursor_col
  LDA #0
  STA LAST_KEY
  RTS

normal_line_start:
  LDA #0
  STA CURSOR_COL
  STA LAST_KEY
  STA RENDER_FLAG
  JSR ensure_cursor_visible
  RTS

normal_line_end:
  JSR get_current_line_len
  BEQ .empty
  SEC
  SBC #1
  STA CURSOR_COL
  JMP .ecv
.empty:
  LDA #0
  STA CURSOR_COL
.ecv:
  LDA #0
  STA LAST_KEY
  STA RENDER_FLAG
  JSR ensure_cursor_visible
  RTS

normal_goto_last:
  SEC
  SBCI16 LINE_COUNT16, $0001, FILE_LINE16
  LDA #0
  STA CURSOR_COL
  STA LAST_KEY
  STA VIEW_TOP_WRAP
  JSR ensure_cursor_visible
  JSR clamp_cursor_col
  RTS

normal_g_key:
  LDA LAST_KEY
  CMP #'g'
  BNE .set_g
  ; gg: go to top
  LDA #0
  STA_LH16 FILE_LINE16
  STA_LH16 VIEW_TOP16
  STA CURSOR_ROW
  STA CURSOR_COL
  STA LAST_KEY
  STA VIEW_TOP_WRAP
  JSR clamp_cursor_col
  RTS
.set_g:
  LDA #'g'
  STA LAST_KEY
  LDA #0
  STA RENDER_FLAG
  RTS

; --- Editing ---

normal_delete_char:
  JSR get_current_line_len
  BEQ .done
  STA LINE_LEN

  LDA CURSOR_COL
  CMP LINE_LEN
  BCS .done

  ; Calculate max deleteable = LINE_LEN - CURSOR_COL
  LDA LINE_LEN
  SEC
  SBC CURSOR_COL
  STA LINE_LEN              ; Reuse as cap

  ; Count pending 'x' keys, add 1 for current key
  LDA #'x'
  STA BUF_TEMP
  JSR count_pending_key      ; Returns count in X
  INX

  ; Cap at max deleteable
  CPX LINE_LEN
  BCC .x_cap_ok
  LDX LINE_LEN
.x_cap_ok:
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
  LDA #0
  STA LAST_KEY
  RTS

normal_d_key:
  LDA LAST_KEY
  CMP #'d'
  BNE .set_d

  ; dd: delete current line
  LDAX16 FILE_LINE16
  JSR buf_delete_line
  LDA #$FF
  STA MODIFIED

  ; Clamp file line if past end
  CMP16 FILE_LINE16, LINE_COUNT16
  BCC .no_clamp
  SEC
  SBCI16 LINE_COUNT16, $0001, FILE_LINE16
.no_clamp:
  LDA #0
  STA LAST_KEY
  JSR clamp_cursor_col
  RTS

.set_d:
  LDA #'d'
  STA LAST_KEY
  RTS

normal_enter_insert:
  LDA #MODE_INSERT
  STA MODE
  LDA #0
  STA LAST_KEY
  RTS

normal_enter_insert_after:
  JSR get_current_line_len
  BEQ .enter
  CMP CURSOR_COL
  BEQ .enter
  BCC .enter
  INC CURSOR_COL
.enter:
  JSR ensure_cursor_visible
  LDA #MODE_INSERT
  STA MODE
  LDA #0
  STA LAST_KEY
  RTS

normal_enter_insert_eol:
  JSR get_current_line_len
  STA CURSOR_COL
  JSR ensure_cursor_visible
  LDA #MODE_INSERT
  STA MODE
  LDA #0
  STA LAST_KEY
  RTS

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
.found_nl:
  INY
  TYA
  CLC
  ADCA16 BUF_PTR16, BUF_PTR16

  LDA #'\n'
  JSR buf_insert_char
  BCS .open_below_full
  JSR buf_rebuild_lines

  INC16 FILE_LINE16
  LDA #0
  STA CURSOR_COL
  JSR ensure_cursor_visible
  LDA #MODE_INSERT
  STA MODE
  LDA #$FF
  STA MODIFIED
  LDA #0
  STA LAST_KEY
  RTS
.open_below_full:
  SET16 str_buffer_full, STR_PTR16
  JSR show_status_message
  LDA #0
  STA LAST_KEY
  RTS

normal_open_above:
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr

  LDA #'\n'
  JSR buf_insert_char
  BCS .open_above_full
  JSR buf_rebuild_lines

  LDA #0
  STA CURSOR_COL
  LDA #MODE_INSERT
  STA MODE
  LDA #$FF
  STA MODIFIED
  LDA #0
  STA LAST_KEY
  RTS
.open_above_full:
  SET16 str_buffer_full, STR_PTR16
  JSR show_status_message
  LDA #0
  STA LAST_KEY
  RTS

normal_enter_command:
  LDA #MODE_COMMAND
  STA MODE
  LDA #0
  STA LAST_KEY
  RTS

; --- Utilities ---

get_current_line_len:
  LDAX16 FILE_LINE16
  JSR buf_get_line_len
  RTS

; Get buffer pointer at cursor position on current line
; Sets BUF_PTR16 to start of FILE_LINE16 + CURSOR_COL
; Clobbers A, X, Y
get_cursor_buf_ptr:
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr
  CLC
  LDA CURSOR_COL
  ADCA16 BUF_PTR16, BUF_PTR16
  RTS

clamp_cursor_col:
  JSR get_current_line_len
  BEQ .set_zero
  SEC
  SBC #1
  CMP CURSOR_COL
  BCS .ok
  STA CURSOR_COL
.ok:
  RTS
.set_zero:
  LDA #0
  STA CURSOR_COL
  RTS
