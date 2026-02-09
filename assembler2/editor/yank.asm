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
