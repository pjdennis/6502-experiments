; ANSI terminal output library
; All routines write escape sequences via io_write

  .zeropage
ANSI_ROW:     .byte    ; Row for cursor positioning (1-based)
ANSI_COL:     .byte    ; Column for cursor positioning (1-based)
STR_PTR16:    .word    ; Pointer for write_string
ANSI_TEMP:    .byte    ; Temp byte for decimal output
ANSI_DIVISOR: .byte    ; Divisor for div_byte

  .code

; Output ESC[ prefix
; Clobbers A
ansi_csi:
  LDA #$1B
  JSR io_write
  LDA #'['
  JMP io_write

; Output ESC[ followed by null-terminated string at STR_PTR16
; Clobbers A, Y
ansi_write_seq:
  JSR ansi_csi
  JMP write_string

; Clear entire screen and move cursor to home position
ansi_clear_screen:
  SET16 ansi_seq_clear, STR_PTR16
  JSR ansi_write_seq
  ; fall through to ansi_cursor_home

; Move cursor to position 1,1
ansi_cursor_home:
  SET16 ansi_seq_home, STR_PTR16
  JMP ansi_write_seq

; Move cursor to ANSI_ROW, ANSI_COL (both 1-based)
; Clobbers A, Y
ansi_move_cursor:
  JSR ansi_csi
  LDA ANSI_ROW
  JSR write_byte_dec
  LDA #';'
  JSR io_write
  LDA ANSI_COL
  JSR write_byte_dec
  LDA #'H'
  JMP io_write

; Clear from cursor to end of current line
ansi_clear_line:
  SET16 ansi_seq_clreol, STR_PTR16
  JMP ansi_write_seq

; Show cursor
ansi_cursor_show:
  SET16 ansi_seq_show, STR_PTR16
  JMP ansi_write_seq

; Hide cursor
ansi_cursor_hide:
  SET16 ansi_seq_hide, STR_PTR16
  JMP ansi_write_seq

; Enable reverse video
ansi_reverse_video:
  SET16 ansi_seq_rev, STR_PTR16
  JMP ansi_write_seq

; Reset to normal video
ansi_normal_video:
  SET16 ansi_seq_norm, STR_PTR16
  JMP ansi_write_seq

; Set scroll region: ANSI_ROW = top (1-based), ANSI_COL = bottom (1-based)
; Emits ESC[top;bottomr
; Clobbers A, X, Y
ansi_set_scroll_region:
  JSR ansi_csi
  LDA ANSI_ROW
  JSR write_byte_dec
  LDA #';'
  JSR io_write
  LDA ANSI_COL
  JSR write_byte_dec
  LDA #'r'
  JMP io_write

; Reset scroll region to full screen: ESC[r
; Clobbers A, Y
ansi_reset_scroll_region:
  SET16 ansi_seq_reset_sr, STR_PTR16
  JMP ansi_write_seq

; Scroll up by A lines (content moves up, blanks at bottom of region)
; Emits ESC[nS. Input: A = count
; Clobbers A, X, Y
ansi_scroll_up:
  PHA
  JSR ansi_csi
  PLA
  JSR write_byte_dec
  LDA #'S'
  JMP io_write

; Scroll down by A lines (content moves down, blanks at top of region)
; Emits ESC[nT. Input: A = count
; Clobbers A, X, Y
ansi_scroll_down:
  PHA
  JSR ansi_csi
  PLA
  JSR write_byte_dec
  LDA #'T'
  JMP io_write

; ANSI sequence string constants
ansi_seq_clear:    .asciiz "2J"
ansi_seq_home:     .asciiz "H"
ansi_seq_clreol:   .asciiz "K"
ansi_seq_show:     .asciiz "?25h"
ansi_seq_hide:     .asciiz "?25l"
ansi_seq_rev:      .asciiz "7m"
ansi_seq_norm:     .asciiz "0m"
ansi_seq_reset_sr: .asciiz "r"

; Write null-terminated string pointed to by STR_PTR16
; Clobbers A, Y
write_string:
  LDY #0
.loop:
  LDA (STR_PTR16),Y
  BEQ .done
  JSR io_write
  INY
  BNE .loop
.done:
  RTS

; Write filename from (FNAME_PTR16), up to 32 chars
; Clobbers A, Y
write_fname:
  LDY #0
.loop:
  LDA (FNAME_PTR16),Y
  BEQ .done
  JSR io_write
  INY
  CPY #32
  BCC .loop
.done:
  RTS

; Move cursor to status line and clear it
; Clobbers A, Y
status_line_clear:
  LDA SCREEN_ROWS
  STA ANSI_ROW
  LDA #1
  STA ANSI_COL
  JSR ansi_move_cursor
  JMP ansi_clear_line

; Show prompt character on status line
; A = prompt character (e.g. ':', '/')
; Clobbers A, Y
show_prompt:
  PHA
  JSR status_line_clear
  PLA
  JSR io_write
  JMP io_flush

; Erase one character on screen: backspace, space, backspace, flush
; Clobbers A
erase_char:
  LDA #'\b'
  JSR io_write
  LDA #' '
  JSR io_write
  LDA #'\b'
  JSR io_write
  JMP io_flush

; Write A (0-255) as decimal digits, no leading zeros
; Clobbers A, X, Y
write_byte_dec:
  STA ANSI_TEMP
  LDY #0        ; leading zero flag: 0 = nothing printed yet

  ; Hundreds digit
  LDA #100
  JSR div_byte
  CMP #0
  BEQ .no_hundreds
  CLC
  ADC #'0'
  JSR io_write
  LDY #1
.no_hundreds:

  ; Tens digit
  LDA #10
  JSR div_byte
  CMP #0
  BNE .print_tens
  CPY #0
  BEQ .no_tens
.print_tens:
  CLC
  ADC #'0'
  JSR io_write
.no_tens:

  ; Ones digit (always printed)
  LDA ANSI_TEMP
  CLC
  ADC #'0'
  JSR io_write
  RTS

; Divide ANSI_TEMP by A via repeated subtraction
; Input: A = divisor, ANSI_TEMP = dividend
; Output: A = quotient, ANSI_TEMP = remainder
; Clobbers: X
div_byte:
  STA ANSI_DIVISOR
  LDA #0
.loop:
  LDX ANSI_TEMP
  CPX ANSI_DIVISOR
  BCC .done
  PHA
  TXA
  SEC
  SBC ANSI_DIVISOR
  STA ANSI_TEMP
  PLA
  CLC
  ADC #1
  JMP .loop
.done:
  RTS
