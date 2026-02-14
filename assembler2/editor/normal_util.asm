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
BATCH_RESTORE_KEY: .byte ; Key to restore to LAST_KEY after batch (0 = none)
BATCH_EXTRA:       .byte ; Number of extra pairs found by batch_pending_pairs (0 = none)

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

; --- Pending key dispatcher ---
; Input: A = low byte, X = high byte of dispatch table address
;        LAST_KEY = first key, BUF_TEMP = second key
; Output: C = 0 if handler was called, C = 1 if no match
; Table format: 5-byte entries [last_key, second_key, flags, handler_lo, handler_hi]
;   second_key = 0 means wildcard (match any second key)
;   flags bit 0: call batch_pending_pairs before handler
;   Terminated by 0 byte
dispatch_pending_key:
  STA DISPATCH_PTR16
  STX DISPATCH_PTR16 + 1
  LDY #0
.loop:
  LDA (DISPATCH_PTR16),Y
  BEQ .no_match
  CMP LAST_KEY
  BNE .next5
  INY
  LDA (DISPATCH_PTR16),Y
  BEQ .matched
  CMP BUF_TEMP
  BNE .next4
.matched:
  INY
  LDA (DISPATCH_PTR16),Y
  LSR
  BCC .no_batch
  TYA
  PHA
  JSR batch_pending_pairs
  PLA
  TAY
.no_batch:
  INY
  LDA (DISPATCH_PTR16),Y
  STA JUMP_TARGET16
  INY
  LDA (DISPATCH_PTR16),Y
  STA JUMP_TARGET16 + 1
  JSR .do_jump
  CLC
  RTS
.next5:
  INY
.next4:
  INY
  INY
  INY
  INY
  JMP .loop
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
; Clobbers: A, X, BUF_TEMP, BUF_PTR16
move_down_x:
.loop:
  STX BUF_TEMP
  CLC
  ADCI16 FILE_LINE16, $0001, BUF_PTR16
  CMP16 BUF_PTR16, LINE_COUNT16
  BCS .done
  INC16 FILE_LINE16
  LDX BUF_TEMP
  DEX
  BNE .loop
.done:
  RTS

; Move up X lines (clamped to first line)
; Input: X = number of lines to move
; Clobbers: A, X, BUF_TEMP
move_up_x:
.loop:
  STX BUF_TEMP
  TST16 FILE_LINE16
  BEQ .done
  DEC16 FILE_LINE16
  LDX BUF_TEMP
  DEX
  BNE .loop
.done:
  RTS

; --- Shared horizontal movement loops ---

; Move left X positions, clamped to col 0
; Input: X = count. Clobbers: A, X
move_left_x:
  TST16 CURSOR_COL16
  BEQ .done
  DEC16 CURSOR_COL16
  DEX
  BNE move_left_x
.done:
  RTS

; Move right X positions, clamped to LINE_LEN16
; Input: X = count, LINE_LEN16 = max col. Clobbers: A, X
move_right_x:
  CMP16 LINE_LEN16, CURSOR_COL16
  BCC .done
  BEQ .done
  INC16 CURSOR_COL16
  DEX
  BNE move_right_x
.done:
  RTS

; --- Count prefix helpers ---

; Check if key starts a multi-key combo by scanning the combo table
; Input: A = low byte, X = high byte of combo table address
;        BUF_TEMP = key code to match
; Output: C = 0 if valid first key (LAST_KEY set), C = 1 if not
; Respects READONLY: skips entries with flags bit 1 set
check_combo_first_key:
  STA DISPATCH_PTR16
  STX DISPATCH_PTR16 + 1
  LDY #0
.loop:
  LDA (DISPATCH_PTR16),Y
  BEQ .no_match
  CMP BUF_TEMP
  BNE .skip
  ; Key matches - check READONLY + editing flag
  LDA READONLY
  BEQ .found
  INY
  INY
  LDA (DISPATCH_PTR16),Y
  DEY
  DEY
  AND #$02
  BEQ .found
.skip:
  TYA
  CLC
  ADC #5
  TAY
  JMP .loop
.found:
  LDA BUF_TEMP
  STA LAST_KEY
  CLC
  RTS
.no_match:
  SEC
  RTS

; Get count and clamp to available lines from FILE_LINE16
; Output: BUF_TEMP16 = clamped count, LINE_LEN16 = FILE_LINE16 (line counter)
; Clobbers: A
get_count_clamp_lines:
  JSR get_count
  SEC
  SBC16 LINE_COUNT16, FILE_LINE16, BUF_LEN16
  CMP16 BUF_TEMP16, BUF_LEN16
  BCC .ok
  CP16 BUF_LEN16, BUF_TEMP16
.ok:
  CP16 FILE_LINE16, LINE_LEN16
  RTS

; --- Insert mode entry helpers ---

; Enter insert mode with render flag=1
enter_insert_mode_render:
  ; fall through

; Enter insert mode and clear count
enter_insert_mode:
  LDA #MODE_INSERT
  STA MODE
  JMP clear_count

; Clear count state: zeroes COUNT16, COUNT_ACTIVE, LAST_KEY
; If BATCH_RESTORE_KEY is set, restores it to LAST_KEY (for partial pair e.g. dddw)
clear_count:
  LDA #0
  STA_LH16 COUNT16
  STA COUNT_ACTIVE
  LDA BATCH_RESTORE_KEY
  STA LAST_KEY
  LDA #0
  STA BATCH_RESTORE_KEY
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

; Get effective count with pending key batching
; Gets count prefix, adds pending matching keys
; Input: BUF_TEMP = key code to match (set by normal_handle_key)
; Output: X = total count (count + pending), capped at 255
; Clobbers: A
get_batched_count:
  JSR get_count
  LDX BUF_TEMP16         ; X = count (low byte, capped at 255)
  STX BUF_DELTA
  JSR count_pending_key  ; X = pending matching keys
  TXA
  CLC
  ADC BUF_DELTA          ; Total = count + pending
  BCS .cap
  TAX
  RTS
.cap:
  LDX #$FF
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

; --- Pair batching for 2-key commands ---

; Batch pending pairs of LAST_KEY + BUF_TEMP from the input stream
; Uses LAST_KEY (first key) and BUF_TEMP (second key) already set by
; pending_key_dispatch. Adds matched pairs to COUNT16.
; Sets BATCH_RESTORE_KEY if a partial pair was consumed.
; Clobbers: A, X
batch_pending_pairs:
  LDX #0                   ; X = extra pairs found
.loop:
  JSR key_ready
  CMP #$FF
  BNE .done                ; No key available, stop
  JSR get_key
  CMP LAST_KEY
  BNE .no_first_match      ; First key doesn't match, push back
  ; First key matches - need second key
  JSR key_ready
  CMP #$FF
  BNE .partial             ; No second key available
  JSR get_key
  CMP BUF_TEMP
  BNE .second_mismatch     ; Second key doesn't match
  ; Full pair matched
  INX
  CPX #BATCH_MAX
  BEQ .done
  JMP .loop
.second_mismatch:
  ; Push back the non-matching second key
  JSR unget_key
.partial:
  ; Save consumed first key for restore after command completes
  LDA LAST_KEY
  STA BATCH_RESTORE_KEY
  JMP .done
.no_first_match:
  ; Push back the non-matching key
  JSR unget_key
.done:
  STX BATCH_EXTRA
  ; Add X extra pairs to COUNT16
  TXA
  BEQ .no_add              ; No extra pairs, nothing to do
  ; Ensure COUNT16 >= 1 (the original command counts as 1)
  PHA                      ; Save extra count
  LDA COUNT16
  ORA COUNT16 + 1
  BNE .has_count
  LDA #1
  STA COUNT16              ; COUNT16 was 0, set to 1
.has_count:
  PLA                      ; Restore extra count
  CLC
  ADC COUNT16
  STA COUNT16
  LDA #0
  ADC COUNT16 + 1
  STA COUNT16 + 1
.no_add:
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
  JSR delete_current_lines
  CLC
  RTS

.ydcl_overflow:
  SEC
  RTS

; Delete N lines starting at FILE_LINE16 without yanking
; Input: BUF_TEMP16 = count of lines (from get_count)
; Adjusts marks, deletes lines, clamps FILE_LINE16
; Clobbers: A, X, Y, BUF_PTR16, BUF_SRC16, BUF_DST16, BUF_LEN16
delete_current_lines:
  LDAX16 FILE_LINE16
  JSR mark_adjust_delete

  LDAX16 FILE_LINE16
  JSR buf_delete_lines

  ; Clamp file line if past end of file
  CMP16 FILE_LINE16, LINE_COUNT16
  BCC .dcl_ok
  SEC
  SBCI16 LINE_COUNT16, 1, FILE_LINE16
.dcl_ok:
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
  ; Fall through to delete_at_cursor

; Delete bytes at cursor position (no yank)
; Input: BUF_LEN16 = number of bytes to delete, cursor position set via CURSOR_COL16
; Shifts buffer, adjusts line table (incremental if no newlines), sets MODIFIED
; Clobbers: A, X, Y, BUF_PTR16, BUF_SRC16, BUF_DST16
delete_at_cursor:
  JSR get_cursor_buf_ptr     ; BUF_PTR16 = cursor position
  ; Scan deleted range for newlines
  CP16 BUF_PTR16, BUF_DST16 ; BUF_DST16 = scan pointer
  LDA #0
  STA NORMAL_TEMP            ; 0 = no newlines found
  PUSH16 BUF_LEN16           ; Save delete count
.scan_nl:
  TST16 BUF_LEN16
  BEQ .scan_done
  LDY #0
  LDA (BUF_DST16),Y
  CMP #'\n'
  BNE .scan_next
  INC NORMAL_TEMP            ; Found newline
.scan_next:
  INC16 BUF_DST16
  DEC16 BUF_LEN16
  JMP .scan_nl
.scan_done:
  POP16 BUF_LEN16            ; Restore delete count
  JSR get_cursor_buf_ptr     ; Recompute BUF_PTR16 (scan clobbered BUF_DST16)
  JSR buf_shift_left_16
  LDA NORMAL_TEMP
  BNE .full_rebuild
  ; Incremental: negate BUF_LEN16 into BUF_SRC16
  LDA #0
  SEC
  SBC BUF_LEN16
  STA BUF_SRC16
  LDA #0
  SBC BUF_LEN16 + 1
  STA BUF_SRC16 + 1
  JSR buf_adjust_lines_apply
  JMP .done
.full_rebuild:
  JSR buf_rebuild_lines
.done:
  LDA #$FF
  STA MODIFIED
  RTS
