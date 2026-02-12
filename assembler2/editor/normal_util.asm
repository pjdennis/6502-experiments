; Normal mode shared utilities - zero-page variables, dispatch, cursor helpers,
; count prefix system, and common yank/delete operations.

  .zeropage

LAST_KEY:       .byte  ; Previous key for multi-key commands (dd, gg, yy, m, ')
LINE_LEN16:     .word  ; Cached length of current line (16-bit)
DISPATCH_PTR16: .word  ; Pointer into dispatch table during scan
JUMP_TARGET16:  .word  ; Target for indirect jump
COUNT16:        .word  ; Accumulated count (0 = no count entered)
COUNT_ACTIVE:   .byte  ; $FF if digits are being entered, $00 otherwise
NORMAL_TEMP:    .byte  ; Temp byte for normal mode operations

  .code

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

; --- Cursor and line utilities ---

; Check if cursor is within current line
; Returns: carry clear = cursor in range (LINE_LEN16 set)
;          carry set = line empty or cursor at/past end
; Clobbers: A, X
check_cursor_in_line:
  JSR get_current_line_len
  STAX16 LINE_LEN16
  TST16 LINE_LEN16
  BEQ .bail
  CMP16 CURSOR_COL16, LINE_LEN16
  BCS .bail
  CLC
  RTS
.bail:
  SEC
  RTS

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

; --- Shared vertical movement loops ---

; Move down X lines (clamped to last line)
; Input: X = number of lines to move
; Sets RENDER_FLAG=0 if any movement occurred
; Clobbers: A, X, BUF_TEMP, BUF_PTR16
move_down_x:
.loop:
  STX BUF_TEMP
  CLC
  ADCI16 FILE_LINE16, $0001, BUF_PTR16
  CMP16 BUF_PTR16, LINE_COUNT16
  BCS .done
  LDA #0
  STA RENDER_FLAG
  INC16 FILE_LINE16
  LDX BUF_TEMP
  DEX
  BNE .loop
.done:
  RTS

; Move up X lines (clamped to first line)
; Input: X = number of lines to move
; Sets RENDER_FLAG=0 if any movement occurred
; Clobbers: A, X, BUF_TEMP
move_up_x:
.loop:
  STX BUF_TEMP
  TST16 FILE_LINE16
  BEQ .done
  LDA #0
  STA RENDER_FLAG
  DEC16 FILE_LINE16
  LDX BUF_TEMP
  DEX
  BNE .loop
.done:
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

; --- Common yank/delete operations ---

; Show yank overflow error: clear yank, show message, clear count
; Used when yank buffer is too full to complete an operation
show_yank_overflow:
  JSR yank_clear
  SET16 str_yank_full, STR_PTR16
  JSR show_status_message
  JMP clear_count

; Yank then delete N lines starting at FILE_LINE16
; Input: BUF_TEMP16 = count of lines (from get_count)
; Returns carry set = yank overflow, carry clear = success
; On success: lines deleted, FILE_LINE16 clamped, YANK_LINES16 set
; Clobbers: A, X, Y, BUF_PTR16, BUF_SRC16, BUF_DST16, BUF_LEN16
yank_delete_current_lines:
  JSR yank_clear
  LDAX16 FILE_LINE16
  JSR yank_add_lines
  BCS .ydcl_overflow

  LDAX16 FILE_LINE16
  JSR mark_adjust_delete

  LDAX16 FILE_LINE16
  JSR buf_delete_lines

  ; Clamp file line if past end of file
  CMP16 FILE_LINE16, LINE_COUNT16
  BCC .ydcl_ok
  SEC
  SBCI16 LINE_COUNT16, 1, FILE_LINE16
.ydcl_ok:
  CLC
  RTS

.ydcl_overflow:
  SEC
  RTS

; Yank chars at cursor position then delete them
; Input: BUF_LEN16 = number of bytes to delete, cursor position set via CURSOR_COL16
; Yanks from cursor, deletes, rebuilds lines, sets MODIFIED
; Clobbers: A, X, Y, BUF_PTR16, BUF_SRC16, BUF_DST16
yank_delete_at_cursor:
  PUSH16 BUF_LEN16           ; Save delete count
  JSR get_cursor_buf_ptr     ; BUF_PTR16 = cursor position
  CP16 BUF_PTR16, BUF_SRC16
  JSR yank_add_chars         ; Clobbers BUF_LEN16, BUF_PTR16
  POP16 BUF_LEN16            ; Restore delete count
  JSR get_cursor_buf_ptr     ; Recompute after yank clobbers
  JSR buf_shift_left_16
  JSR buf_rebuild_lines
  LDA #$FF
  STA MODIFIED
  RTS
