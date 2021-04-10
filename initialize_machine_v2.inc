initialize_machine:

  ; Initialize 6522 port A (display control and shift register output enable)
  lda #(E | RW | RS | SOEB)
  sta DDRA
  lda #SOEB
  sta PORTA ; Disable the shift register output

  ; Initialize 6522 port B (8 bit data lines)
  lda #%11111111 ; Set all pins on port B to output
  sta DDRB

  jmp program_start

