initialize_machine:

  ; Initialize 6522 port A (display control and shift register output enable)
  lda #(E | RW | RS | SOEB | SOLB | START | PARITY)
  sta DDRA

  ; Disable input shift register; prepare to initialize output shift register
  lda #(SOEB | SOLB | START | PARITY)
  sta PORTA

  ; Initialize 6522 port B (8 bit data lines)
  lda #%11111111 ; Set all pins on port B to output
  sta DDRB

  ; Initialize output shift register
  lda #%11111111
  sta PORTB
  lda #(SOEB | START | PARITY)
  sta PORTA
  lda #(SOEB | SOLB | START | PARITY)
  sta PORTA

  jmp program_start

