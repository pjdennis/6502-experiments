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
  LDA YANK_END16
  SBC #<YANK_BUF
  STA BUF_LEN16
  LDA YANK_END16 + 1
  SBC #>YANK_BUF
  STA BUF_LEN16 + 1
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
  JSR yank_get_size
  BCS .paste_empty           ; Nothing to paste

  ; Find insertion point: after current line's newline
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr       ; BUF_PTR16 = start of current line
  LDY #0
.find_nl_below:
  LDA (BUF_PTR16),Y
  CMP #'\n'
  BEQ .found_nl_below
  INY
  BNE .find_nl_below
.found_nl_below:
  ; BUF_PTR16 + Y + 1 = insertion point (after newline)
  INY
  TYA
  CLC
  ADCA16 BUF_PTR16, BUF_PTR16

  ; Set up source and size for buf_insert_block
  SET16 YANK_BUF, BUF_SRC16
  ; BUF_LEN16 already set by yank_get_size

  JSR buf_insert_block
  BCS .paste_full

  JSR buf_rebuild_lines

  ; Move cursor to first pasted line
  INC16 FILE_LINE16
  LDA #0
  STA CURSOR_COL
  JSR ensure_cursor_visible
  JSR clamp_cursor_col
  CLC
  RTS

.paste_full:
  SET16 str_buffer_full, STR_PTR16
  JSR show_status_message
  SEC
  RTS

.paste_empty:
  SEC
  RTS

; Paste yank buffer above current line
; Inserts yank content at start of current line
; Sets cursor to first pasted line (same line number), col 0
; Returns carry set = buffer full or empty yank, carry clear = success
yank_paste_above:
  JSR yank_get_size
  BCS .paste_above_empty     ; Nothing to paste

  ; Insertion point: start of current line
  LDAX16 FILE_LINE16
  JSR buf_get_line_ptr       ; BUF_PTR16 = start of current line

  ; Set up source and size for buf_insert_block
  SET16 YANK_BUF, BUF_SRC16
  ; BUF_LEN16 already set by yank_get_size

  JSR buf_insert_block
  BCS .paste_above_full

  JSR buf_rebuild_lines

  ; Cursor stays at same line number (which is now the first pasted line)
  LDA #0
  STA CURSOR_COL
  JSR ensure_cursor_visible
  JSR clamp_cursor_col
  CLC
  RTS

.paste_above_full:
  SET16 str_buffer_full, STR_PTR16
  JSR show_status_message
  SEC
  RTS

.paste_above_empty:
  SEC
  RTS
