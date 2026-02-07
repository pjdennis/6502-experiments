; Hello world console test program
; Queries terminal size, clears screen, displays dimensions,
; reads keypresses and shows their codes, exits on 'q'

* = $0400

  .include environment.asm

  .zeropage
TEMP_VAL  .data $00

  .code

main
  JSR clear_screen

  ; Print "Terminal size: "
  LDX #$00
.print_size_msg
  LDA size_msg,X
  BEQ .print_rows
  JSR write_b
  INX
  BNE .print_size_msg

.print_rows
  JSR term_rows
  JSR print_byte_dec

  LDA #'x'
  JSR write_b

  JSR term_cols
  JSR print_byte_dec

  LDA #$0A
  JSR write_b

  ; Print instructions
  LDX #$00
.print_instr
  LDA instr_msg,X
  BEQ .flush_and_loop
  JSR write_b
  INX
  BNE .print_instr

.flush_and_loop
  LDA #$0A
  JSR write_b
  JSR con_flush

  ; Main loop: read key, display its code, exit on 'q'
.key_loop
  JSR con_read
  STA TEMP_VAL

  CMP #'q'
  BEQ .quit

  ; Print "Key: $"
  LDX #$00
.print_key_msg
  LDA key_msg,X
  BEQ .print_key_val
  JSR write_b
  INX
  BNE .print_key_msg

.print_key_val
  LDA TEMP_VAL
  JSR print_hex

  LDA #' '
  JSR write_b
  LDA #'('
  JSR write_b

  ; Print char if printable
  LDA TEMP_VAL
  CMP #$20
  BCC .not_printable
  CMP #$7F
  BCS .not_printable
  JSR write_b
  JMP .after_char
.not_printable
  LDA #'.'
  JSR write_b
.after_char
  LDA #')'
  JSR write_b
  LDA #$0D
  JSR write_b
  LDA #$0A
  JSR write_b
  JSR con_flush
  JMP .key_loop

.quit
  JSR clear_screen
  JSR con_flush
  LDA #$00
  JSR exit


; === Utility routines ===

; Clear screen and move cursor to home
clear_screen
  LDA #$1B
  JSR write_b
  LDA #'['
  JSR write_b
  LDA #'2'
  JSR write_b
  LDA #'J'
  JSR write_b
  LDA #$1B
  JSR write_b
  LDA #'['
  JSR write_b
  LDA #'H'
  JSR write_b
  RTS

; Print A as 2-digit hex
print_hex
  PHA
  LSR
  LSR
  LSR
  LSR
  JSR .hex_nibble
  PLA
  AND #$0F
.hex_nibble
  CMP #$0A
  BCC .hex_digit
  CLC
  ADC #'A'-$0A
  JSR write_b
  RTS
.hex_digit
  CLC
  ADC #'0'
  JSR write_b
  RTS

; Print A (0-255) as decimal, no leading zeros
; Clobbers A, X, Y
print_byte_dec
  STA TEMP_VAL
  LDY #$00       ; leading zero suppression: 0=nothing printed yet

  ; Hundreds digit
  LDX #$00
.hundreds_loop
  LDA TEMP_VAL
  CMP #$64
  BCC .hundreds_done
  SEC
  SBC #$64
  STA TEMP_VAL
  INX
  JMP .hundreds_loop
.hundreds_done
  CPX #$00
  BEQ .no_hundreds
  TXA
  CLC
  ADC #'0'
  JSR write_b
  LDY #$01
.no_hundreds

  ; Tens digit
  LDX #$00
.tens_loop
  LDA TEMP_VAL
  CMP #$0A
  BCC .tens_done
  SEC
  SBC #$0A
  STA TEMP_VAL
  INX
  JMP .tens_loop
.tens_done
  CPX #$00
  BNE .print_tens
  CPY #$00
  BEQ .no_tens
.print_tens
  TXA
  CLC
  ADC #'0'
  JSR write_b
.no_tens

  ; Ones digit (always printed)
  LDA TEMP_VAL
  CLC
  ADC #'0'
  JSR write_b
  RTS


; === Data ===

size_msg  .data "Terminal size: " $00
instr_msg .data "Press keys to see codes, 'q' to quit" $00
key_msg   .data "Key: $" $00
