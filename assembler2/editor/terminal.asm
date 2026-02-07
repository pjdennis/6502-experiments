; ANSI terminal output library
; All routines write escape sequences via write_b

  .zeropage
ANSI_ROW     .data $00  ; Row for cursor positioning (1-based)
ANSI_COL     .data $00  ; Column for cursor positioning (1-based)
STR_PTR16    .data $0000 ; Pointer for write_string
ANSI_TEMP    .data $00   ; Temp byte for decimal output

  .code

; Clear entire screen and move cursor to home position
ansi_clear_screen
  LDA #$1B
  JSR write_b
  LDA #'['
  JSR write_b
  LDA #'2'
  JSR write_b
  LDA #'J'
  JSR write_b
  ; fall through to ansi_cursor_home

; Move cursor to position 1,1
ansi_cursor_home
  LDA #$1B
  JSR write_b
  LDA #'['
  JSR write_b
  LDA #'H'
  JSR write_b
  RTS

; Move cursor to ANSI_ROW, ANSI_COL (both 1-based)
; Clobbers A, Y
ansi_move_cursor
  LDA #$1B
  JSR write_b
  LDA #'['
  JSR write_b
  LDA ANSI_ROW
  JSR write_byte_dec
  LDA #';'
  JSR write_b
  LDA ANSI_COL
  JSR write_byte_dec
  LDA #'H'
  JSR write_b
  RTS

; Clear from cursor to end of current line
ansi_clear_line
  LDA #$1B
  JSR write_b
  LDA #'['
  JSR write_b
  LDA #'K'
  JSR write_b
  RTS

; Show cursor
ansi_cursor_show
  LDA #$1B
  JSR write_b
  LDA #'['
  JSR write_b
  LDA #'?'
  JSR write_b
  LDA #'2'
  JSR write_b
  LDA #'5'
  JSR write_b
  LDA #'h'
  JSR write_b
  RTS

; Hide cursor
ansi_cursor_hide
  LDA #$1B
  JSR write_b
  LDA #'['
  JSR write_b
  LDA #'?'
  JSR write_b
  LDA #'2'
  JSR write_b
  LDA #'5'
  JSR write_b
  LDA #'l'
  JSR write_b
  RTS

; Enable reverse video
ansi_reverse_video
  LDA #$1B
  JSR write_b
  LDA #'['
  JSR write_b
  LDA #'7'
  JSR write_b
  LDA #'m'
  JSR write_b
  RTS

; Reset to normal video
ansi_normal_video
  LDA #$1B
  JSR write_b
  LDA #'['
  JSR write_b
  LDA #'0'
  JSR write_b
  LDA #'m'
  JSR write_b
  RTS

; Write null-terminated string pointed to by STR_PTR16
; Clobbers A, Y
write_string
  LDY #$00
.loop
  LDA (STR_PTR16),Y
  BEQ .done
  JSR write_b
  INY
  BNE .loop
.done
  RTS

; Write A (0-255) as decimal digits, no leading zeros
; Clobbers A, X, Y
write_byte_dec
  STA ANSI_TEMP
  LDY #$00      ; leading zero flag: 0 = nothing printed yet

  ; Hundreds digit
  LDA #$00
.hundreds_loop
  LDX ANSI_TEMP
  CPX #$64
  BCC .hundreds_done
  PHA
  TXA
  SEC
  SBC #$64
  STA ANSI_TEMP
  PLA
  CLC
  ADC #$01
  JMP .hundreds_loop
.hundreds_done
  ; A = hundreds count
  CMP #$00
  BEQ .no_hundreds
  CLC
  ADC #'0'
  JSR write_b
  LDY #$01
.no_hundreds

  ; Tens digit
  LDA #$00
.tens_loop
  LDX ANSI_TEMP
  CPX #$0A
  BCC .tens_done
  PHA
  TXA
  SEC
  SBC #$0A
  STA ANSI_TEMP
  PLA
  CLC
  ADC #$01
  JMP .tens_loop
.tens_done
  ; A = tens count
  CMP #$00
  BNE .print_tens
  CPY #$00
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
