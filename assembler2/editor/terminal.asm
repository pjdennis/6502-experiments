; ANSI terminal output library
; All routines write escape sequences via write_b

  .zeropage
ANSI_ROW     .byte 0    ; Row for cursor positioning (1-based)
ANSI_COL     .byte 0    ; Column for cursor positioning (1-based)
STR_PTR16    .word 0    ; Pointer for write_string
ANSI_TEMP    .byte 0    ; Temp byte for decimal output

  .code

; Output ESC[ prefix
; Clobbers A
ansi_csi
  LDA #$1B
  JSR write_b
  LDA #'['
  JMP write_b

; Output ESC[ followed by null-terminated string at STR_PTR16
; Clobbers A, Y
ansi_write_seq
  JSR ansi_csi
  JMP write_string

; Clear entire screen and move cursor to home position
ansi_clear_screen
  SET16 ansi_seq_clear, STR_PTR16
  JSR ansi_write_seq
  ; fall through to ansi_cursor_home

; Move cursor to position 1,1
ansi_cursor_home
  SET16 ansi_seq_home, STR_PTR16
  JMP ansi_write_seq

; Move cursor to ANSI_ROW, ANSI_COL (both 1-based)
; Clobbers A, Y
ansi_move_cursor
  JSR ansi_csi
  LDA ANSI_ROW
  JSR write_byte_dec
  LDA #';'
  JSR write_b
  LDA ANSI_COL
  JSR write_byte_dec
  LDA #'H'
  JMP write_b

; Clear from cursor to end of current line
ansi_clear_line
  SET16 ansi_seq_clreol, STR_PTR16
  JMP ansi_write_seq

; Show cursor
ansi_cursor_show
  SET16 ansi_seq_show, STR_PTR16
  JMP ansi_write_seq

; Hide cursor
ansi_cursor_hide
  SET16 ansi_seq_hide, STR_PTR16
  JMP ansi_write_seq

; Enable reverse video
ansi_reverse_video
  SET16 ansi_seq_rev, STR_PTR16
  JMP ansi_write_seq

; Reset to normal video
ansi_normal_video
  SET16 ansi_seq_norm, STR_PTR16
  JMP ansi_write_seq

; ANSI sequence string constants
ansi_seq_clear  .asciiz "2J"
ansi_seq_home   .asciiz "H"
ansi_seq_clreol .asciiz "K"
ansi_seq_show   .asciiz "?25h"
ansi_seq_hide   .asciiz "?25l"
ansi_seq_rev    .asciiz "7m"
ansi_seq_norm   .asciiz "0m"

; Write null-terminated string pointed to by STR_PTR16
; Clobbers A, Y
write_string
  LDY #0
.loop
  LDA (STR_PTR16),Y
  BEQ .done
  JSR write_b
  INY
  BNE .loop
.done
  RTS

; Write filename from (FNAME_PTR16), up to 32 chars
; Clobbers A, Y
write_fname
  LDY #0
.loop
  LDA (FNAME_PTR16),Y
  BEQ .done
  JSR write_b
  INY
  CPY #32
  BCC .loop
.done
  RTS

; Write A (0-255) as decimal digits, no leading zeros
; Clobbers A, X, Y
write_byte_dec
  STA ANSI_TEMP
  LDY #0        ; leading zero flag: 0 = nothing printed yet

  ; Hundreds digit
  LDA #0
.hundreds_loop
  LDX ANSI_TEMP
  CPX #100
  BCC .hundreds_done
  PHA
  TXA
  SEC
  SBC #100
  STA ANSI_TEMP
  PLA
  CLC
  ADC #1
  JMP .hundreds_loop
.hundreds_done
  ; A = hundreds count
  CMP #0
  BEQ .no_hundreds
  CLC
  ADC #'0'
  JSR write_b
  LDY #1
.no_hundreds

  ; Tens digit
  LDA #0
.tens_loop
  LDX ANSI_TEMP
  CPX #10
  BCC .tens_done
  PHA
  TXA
  SEC
  SBC #10
  STA ANSI_TEMP
  PLA
  CLC
  ADC #1
  JMP .tens_loop
.tens_done
  ; A = tens count
  CMP #0
  BNE .print_tens
  CPY #0
  BEQ .no_tens
.print_tens
  CLC
  ADC #'0'
  JSR write_b
.no_tens

  ; Ones digit (always printed)
  LDA ANSI_TEMP
  CLC
  ADC #'0'
  JSR write_b
  RTS
