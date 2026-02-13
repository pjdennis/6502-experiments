; Normal mode movement commands - cursor motion, search, marks, yank

; --- Movement ---

normal_move_left:
  JSR get_batched_count
  JSR move_left_x
  JMP clear_count

normal_move_right:
  JSR get_batched_count
  ; Hoist line length calculation outside loop (line doesn't change)
  STX BUF_TEMP           ; Save count
  JSR get_current_line_len
  STAX16 LINE_LEN16
  LDX BUF_TEMP           ; Restore count
  TST16 LINE_LEN16
  BEQ .right_done        ; Empty line
  SEC
  SBCI16 LINE_LEN16, 1, LINE_LEN16  ; LINE_LEN16 = len - 1
  JSR move_right_x
.right_done:
  JMP clear_count

normal_move_down:
  JSR get_batched_count
  JSR move_down_x
  JSR clamp_cursor_col
  JMP clear_count

normal_move_up:
  JSR get_batched_count
  JSR move_up_x
  JSR clamp_cursor_col
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
  JSR clamp_cursor_col
  JMP clear_count

normal_line_start:
  LDA #0
  STA_LH16 CURSOR_COL16
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
  JSR clamp_cursor_col
  JMP clear_count

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

; --- Yank ---

; yy: yank N lines starting at current line
; When batched (BATCH_EXTRA > 0): cap count to 1. Batched extra pairs
; have implicit count=1, and the last yy overwrites previous yanks,
; so only 1 line should be yanked.
do_yy:
  JSR yank_clear
  JSR get_count              ; BUF_TEMP16 = count (16-bit)
  LDA BATCH_EXTRA
  BEQ .do_yank
  LDA #1
  STA BUF_TEMP16
  LDA #0
  STA BUF_TEMP16 + 1
.do_yank:
  LDAX16 FILE_LINE16
  JSR yank_add_lines
  BCS .overflow
  JMP clear_count            ; Done - don't set MODIFIED

.overflow:
  JMP show_yank_overflow

; --- Search ---

normal_search:
  JSR search_handle
  JMP clear_count

normal_search_backward:
  JSR search_backward_handle
  JMP clear_count

normal_find_next:
  LDA SEARCH_LEN
  BEQ search_find_none
  LDA SEARCH_DIR
  JMP search_find_dir

normal_find_prev:
  LDA SEARCH_LEN
  BEQ search_find_none
  LDA SEARCH_DIR
  EOR #1

search_find_dir:
  BNE .backward
  JSR search_forward
  JMP clear_count
.backward:
  JSR search_backward
  JMP clear_count

search_find_none:
  JMP clear_count

; --- Marks ---

; Execute mark set with register letter in BUF_TEMP
do_mark_set:
  LDA BUF_TEMP
  JSR mark_set
  JMP clear_count

; Execute mark goto with register letter in BUF_TEMP
do_mark_goto:
  LDA BUF_TEMP
  JSR mark_get
  BCS .mark_not_set
  STAX16 FILE_LINE16
  LDA #0
  STA_LH16 CURSOR_COL16
  JSR clamp_cursor_col
  JMP clear_count
.mark_not_set:
  SET16 str_mark_not_set, STR_PTR16
  JSR show_status_message
  JMP clear_count

; --- Mode switch ---

normal_enter_command:
  LDA #MODE_COMMAND
  STA MODE
  JMP clear_count
