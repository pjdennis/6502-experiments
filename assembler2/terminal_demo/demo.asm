; Simple serial terminal demo
; Clears screen, prints greeting, echoes typed characters
; Press 'q' to quit

* = $0400
  JMP main
  .include 23/environment.asm

; Print a null-terminated string via serial
; String address in A (low) and X (high)
print_str:
  STA $10
  STX $11
  LDY #$00
.loop:
  LDA ($10),Y
  BEQ .done
  JSR serial_write
  INY
  BNE .loop
.done:
  RTS

main:
  ; Clear screen: ESC[2J ESC[H
  LDA #<clear_seq
  LDX #>clear_seq
  JSR print_str

  ; Print greeting
  LDA #<greeting
  LDX #>greeting
  JSR print_str

  ; Main loop: poll serial, echo characters
.loop:
  JSR serial_read
  BCS .loop           ; No data available, keep polling

  ; Check for 'q' to quit
  CMP #'q'
  BEQ .quit

  ; Echo the character
  JSR serial_write
  JMP .loop

.quit:
  ; Restore screen: print newline, then exit
  LDA #$0A
  JSR serial_write
  LDA #$00
  JMP exit

clear_seq:
  .byte $1B, "[2J"
  .byte $1B, "[H"
  .byte $00

greeting:
  .byte "Serial Terminal Demo - type characters (q to quit)", $0D, $0A, $00
