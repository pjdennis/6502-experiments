; Yank (copy) buffer for cut/copy/paste operations
;
; The yank buffer stores line content for paste operations.
; Lines are stored contiguously with newline delimiters, like the text buffer.
;
; Memory layout:
;   YANK_BUF  ($E100) - Start of yank buffer
;   YANK_LIMIT ($E500) - End of yank buffer (1KB)

YANK_BUF   = $E100
YANK_LIMIT = $E500

  .zeropage

YANK_END16:    .word     ; Points one past last byte in yank buffer
YANK_LINES:    .byte     ; Number of lines in yank buffer
YANK_SIZE16:   .word     ; Single yank size for paste operations

  .code

; Initialize yank buffer (call once at startup)
yank_init:
; Clear yank buffer (reset to empty)
yank_clear:
  SET16 YANK_BUF, YANK_END16
  LDA #0
  STA YANK_LINES
  RTS

; Add N contiguous lines to yank buffer in one bulk copy
; Input: A/X = first line number (low/high), BUF_TEMP = count of lines
; Clamps count to available lines. Uses mem_copy_down for page-optimized copy.
; Returns carry set = yank buffer full, carry clear = success
; On success: YANK_END16 updated, YANK_LINES = actual lines copied
yank_add_lines:
  STAX16 BUF_SRC16           ; BUF_SRC16 = first line number

  ; Clamp count: actual = min(count, LINE_COUNT16 - first_line)
  SEC
  SBC16 LINE_COUNT16, BUF_SRC16, BUF_LEN16  ; BUF_LEN16 = available lines
  ; If available < count, use available
  LDA BUF_LEN16 + 1
  BNE .count_ok           ; Available >= 256, count (8-bit) is fine
  LDA BUF_TEMP
  CMP BUF_LEN16
  BCC .count_ok
  BEQ .count_ok
  LDA BUF_LEN16
  STA BUF_TEMP                ; Clamp count
.count_ok:

  ; Look up LINE_TBL[first_line] → start address
  LDAX16 BUF_SRC16
  JSR buf_get_line_ptr        ; BUF_PTR16 = start of first line
  PUSH16 BUF_PTR16            ; Save start address on stack

  ; Compute end line number = first_line + actual_count
  CLC
  LDA BUF_SRC16
  ADC BUF_TEMP
  STA BUF_SRC16
  LDA BUF_SRC16 + 1
  ADC #0
  STA BUF_SRC16 + 1          ; BUF_SRC16 = end line number

  ; If end line >= LINE_COUNT16, end address = BUF_END16
  CMP16 BUF_SRC16, LINE_COUNT16
  BCC .get_end_ptr
  CP16 BUF_END16, BUF_PTR16  ; BUF_PTR16 = end address = BUF_END16
  JMP .have_end

.get_end_ptr:
  LDAX16 BUF_SRC16
  JSR buf_get_line_ptr        ; BUF_PTR16 = start of end line = our end addr

.have_end:
  ; BUF_PTR16 = end address
  POP16 BUF_SRC16            ; BUF_SRC16 = start address

  ; Compute size = BUF_PTR16 - BUF_SRC16
  SEC
  SBC16 BUF_PTR16, BUF_SRC16, BUF_LEN16

  ; Check if YANK_END16 + size <= YANK_LIMIT
  CLC
  ADC16 YANK_END16, BUF_LEN16, BUF_DST16
  LDA BUF_DST16 + 1
  CMP #>YANK_LIMIT
  BCC .has_room
  BNE .full
  LDA BUF_DST16
  BEQ .has_room           ; Exactly at limit is ok
  BNE .full
.has_room:

  ; mem_copy_down(start, end, YANK_END16)
  ;   BUF_SRC16 = start (already set)
  ;   BUF_PTR16 = end (already set)
  ;   BUF_DST16 = YANK_END16
  CP16 YANK_END16, BUF_DST16
  JSR mem_copy_down            ; Preserves BUF_PTR16

  ; YANK_END16 += size
  CLC
  ADC16 YANK_END16, BUF_LEN16, YANK_END16

  ; YANK_LINES = actual count
  LDA BUF_TEMP
  STA YANK_LINES

  CLC
  RTS

.full:
  SEC
  RTS

; Compute yank buffer size in BUF_LEN16
; Returns carry set if yank buffer empty, carry clear if has content
yank_get_size:
  SEC
  SBCI16 YANK_END16, YANK_BUF, BUF_LEN16
  ; Check if size is zero
  ORA BUF_LEN16
  BEQ .empty
  CLC
  RTS
.empty:
  SEC
  RTS

; Paste yank buffer below current line
; Inserts yank content after current line's newline
; Sets cursor to first pasted line, col 0
; Returns carry set = buffer full or empty yank, carry clear = success
yank_paste_below:
  LDA #1
  STA BUF_TEMP
  ; Fall through

; Paste yank buffer below current line, N times in one batch operation
; Input: BUF_TEMP = count of times to paste
; Returns carry set = error (empty/full), carry clear = success
yank_paste_below_n:
  JSR yank_paste_setup
  BCC .has_data
  RTS
.has_data:

  ; Find insertion point: after current line's newline
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr        ; BUF_PTR16 = start of current line
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
  ADCA16 BUF_PTR16, BUF_PTR16 ; BUF_PTR16 = insertion point (after newline)

  JSR yank_paste_core
  BCS .done

  ; Move cursor to first pasted line
  INC16 FILE_LINE16
  LDA #0
  STA_LH16 CURSOR_COL16
  JSR ensure_cursor_visible
  JSR clamp_cursor_col
  CLC
.done:
  RTS

; Paste yank buffer above current line
; Inserts yank content at start of current line
; Sets cursor to first pasted line (same line number), col 0
; Returns carry set = buffer full or empty yank, carry clear = success
yank_paste_above:
  LDA #1
  STA BUF_TEMP
  ; Fall through

; Paste yank buffer above current line, N times in one batch operation
; Input: BUF_TEMP = count of times to paste
; Returns carry set = error (empty/full), carry clear = success
yank_paste_above_n:
  JSR yank_paste_setup
  BCC .has_data
  RTS
.has_data:

  ; Insertion point: start of current line
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr        ; BUF_PTR16 = start of current line

  JSR yank_paste_core
  BCS .done

  ; Cursor stays at same line number
  LDA #0
  STA_LH16 CURSOR_COL16
  JSR ensure_cursor_visible
  JSR clamp_cursor_col
  CLC
.done:
  RTS

; Compute yank size and total paste size
; Input: BUF_TEMP = paste count
; Output: BUF_LEN16 = total size, YANK_SIZE16 = single size
; Returns carry set if yank buffer empty, carry clear if ready
yank_paste_setup:
  JSR yank_get_size           ; BUF_LEN16 = single yank size
  BCC .has_data
  RTS                         ; Empty yank, carry already set
.has_data:
  CP16 BUF_LEN16, YANK_SIZE16 ; YANK_SIZE16 = single size
  LDX BUF_TEMP
  DEX
  BEQ .done
.calc:
  CLC
  ADC16 BUF_LEN16, YANK_SIZE16, BUF_LEN16
  DEX
  BNE .calc
.done:
  CLC
  RTS

; Shift right, copy yank buffer N times into gap, rebuild lines
; Input: BUF_PTR16 = insertion point, BUF_LEN16 = total size, BUF_TEMP = count
; Returns carry set = buffer full, carry clear = success
yank_paste_core:
  ; Shift right to make room
  JSR buf_shift_right_16
  BCC .shift_ok
  SET16 str_buffer_full, STR_PTR16
  JSR show_status_message
  SEC
  RTS
.shift_ok:

  ; Copy yank buffer into gap N times using mem_copy_down
  ; BUF_PTR16 = insertion point (gap start)
  LDX BUF_TEMP
.copy_loop:
  TXA
  PHA
  ; Set up mem_copy_down: src=YANK_BUF, end=YANK_END16, dst=write_pos
  PUSH16 BUF_PTR16            ; Save write position
  CP16 BUF_PTR16, BUF_DST16   ; BUF_DST16 = write position
  SET16 YANK_BUF, BUF_SRC16
  CP16 YANK_END16, BUF_PTR16  ; BUF_PTR16 = end of yank data
  JSR mem_copy_down            ; Preserves BUF_PTR16
  POP16 BUF_PTR16             ; Restore write position
  ; Advance write position by single size
  CLC
  ADC16 BUF_PTR16, YANK_SIZE16, BUF_PTR16
  PLA
  TAX
  DEX
  BNE .copy_loop

  ; Rebuild lines once
  JSR buf_rebuild_lines
  CLC
  RTS
