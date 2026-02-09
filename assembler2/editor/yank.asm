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

  .code

; Initialize yank buffer (call once at startup)
yank_init:
; Clear yank buffer (reset to empty)
yank_clear:
  SET16 YANK_BUF, YANK_END16
  LDA #0
  STA YANK_LINES
  RTS

; Add line N (in A/X low/high) to yank buffer
; Copies line content + newline from text buffer into yank buffer
; Returns carry set = yank buffer full, carry clear = success
yank_add_line:
  JSR buf_get_line_ptr     ; BUF_PTR16 = start of line

  ; Copy bytes until newline (inclusive)
  LDY #0
.copy_loop:
  ; Check if yank buffer is full
  LDA YANK_END16 + 1
  CMP #>YANK_LIMIT
  BCC .yank_has_room
  LDA YANK_END16
  CMP #<YANK_LIMIT
  BCS .yank_full
.yank_has_room:
  LDA (BUF_PTR16),Y
  PHA                      ; Save byte
  ; Store in yank buffer
  STY BUF_TEMP             ; Save Y (offset into source line)
  LDY #0
  PLA                      ; Restore byte
  STA (YANK_END16),Y
  INC16 YANK_END16
  LDY BUF_TEMP             ; Restore source offset
  LDA (BUF_PTR16),Y        ; Re-read to check for newline
  CMP #'\n'
  BEQ .line_done
  INY
  BNE .copy_loop
  ; Line longer than 255 chars - shouldn't happen in practice
  JMP .copy_loop

.line_done:
  INC YANK_LINES
  CLC
  RTS

.yank_full:
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
  JSR yank_get_size           ; BUF_LEN16 = single yank size
  BCC .pbn_has_data
  RTS                         ; Empty yank, carry already set
.pbn_has_data:

  ; Calculate total size = single × count
  CP16 BUF_LEN16, BUF_DST16  ; BUF_DST16 = single size
  LDX BUF_TEMP
  DEX
  BEQ .pbn_total_done
.pbn_calc:
  CLC
  ADC16 BUF_LEN16, BUF_DST16, BUF_LEN16
  DEX
  BNE .pbn_calc
.pbn_total_done:
  ; BUF_LEN16 = total size, BUF_DST16 = single size

  ; Save single size on stack
  PUSH16 BUF_DST16

  ; Find insertion point: after current line's newline
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr        ; BUF_PTR16 = start of current line
  LDY #0
.pbn_find_nl:
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .pbn_found_nl
  INY
  BNE .pbn_find_nl
.pbn_found_nl:
  INY
  TYA
  CLC
  ADCA16 BUF_PTR16, BUF_PTR16 ; BUF_PTR16 = insertion point (after newline)

  ; Shift right to make room: BUF_PTR16 = insert point, BUF_LEN16 = total size
  JSR buf_shift_right_16
  POP16 BUF_DST16            ; Restore single size (PLA doesn't affect carry)
  BCC .pbn_shift_ok
  ; Buffer full
  SET16 str_buffer_full, STR_PTR16
  JSR show_status_message
  SEC
  RTS
.pbn_shift_ok:

  ; Copy yank buffer into gap N times
  ; BUF_PTR16 still points to insertion point (gap start)
  LDX BUF_TEMP
.pbn_copy_loop:
  TXA
  PHA
  ; Copy single yank content: YANK_BUF → BUF_PTR16
  SET16 YANK_BUF, BUF_SRC16
  CP16 BUF_DST16, BUF_LEN16  ; BUF_LEN16 = single size (counter)
.pbn_copy_bytes:
  LDY #0
  LDA (BUF_SRC16),Y
  STA (BUF_PTR16),Y
  INC16 BUF_SRC16
  INC16 BUF_PTR16
  DEC16 BUF_LEN16
  TST16 BUF_LEN16
  BNE .pbn_copy_bytes

  PLA
  TAX
  DEX
  BNE .pbn_copy_loop

  ; Rebuild lines once
  JSR buf_rebuild_lines

  ; Move cursor to first pasted line
  INC16 FILE_LINE16
  LDA #0
  STA CURSOR_COL
  JSR ensure_cursor_visible
  JSR clamp_cursor_col
  CLC
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
  JSR yank_get_size           ; BUF_LEN16 = single yank size
  BCC .pan_has_data
  RTS                         ; Empty yank, carry already set
.pan_has_data:

  ; Calculate total size = single × count
  CP16 BUF_LEN16, BUF_DST16  ; BUF_DST16 = single size
  LDX BUF_TEMP
  DEX
  BEQ .pan_total_done
.pan_calc:
  CLC
  ADC16 BUF_LEN16, BUF_DST16, BUF_LEN16
  DEX
  BNE .pan_calc
.pan_total_done:

  ; Save single size on stack
  PUSH16 BUF_DST16

  ; Insertion point: start of current line
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr        ; BUF_PTR16 = start of current line

  ; Shift right to make room
  JSR buf_shift_right_16
  POP16 BUF_DST16
  BCC .pan_shift_ok
  ; Buffer full
  SET16 str_buffer_full, STR_PTR16
  JSR show_status_message
  SEC
  RTS
.pan_shift_ok:

  ; Copy yank buffer into gap N times
  LDX BUF_TEMP
.pan_copy_loop:
  TXA
  PHA
  SET16 YANK_BUF, BUF_SRC16
  CP16 BUF_DST16, BUF_LEN16
.pan_copy_bytes:
  LDY #0
  LDA (BUF_SRC16),Y
  STA (BUF_PTR16),Y
  INC16 BUF_SRC16
  INC16 BUF_PTR16
  DEC16 BUF_LEN16
  TST16 BUF_LEN16
  BNE .pan_copy_bytes

  PLA
  TAX
  DEX
  BNE .pan_copy_loop

  ; Rebuild lines once
  JSR buf_rebuild_lines

  ; Cursor stays at same line number
  LDA #0
  STA CURSOR_COL
  JSR ensure_cursor_visible
  JSR clamp_cursor_col
  CLC
  RTS
