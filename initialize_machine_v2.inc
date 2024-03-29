initialize_machine:

  ; Initialize 6522 port A (display control and shift register output enable)
  lda #(E | RW | RS | SOEB | SOLB | START | PARITY | LED)
  sta DDRA

  ; Initialize 6522 port B (8 bit data lines)
  lda #%11111111 ; Set all pins on port B to output
  sta DDRB

  ; Disable input shift register; prepare to initialize output shift register; turn off LED
  lda #(SOEB | SOLB | START | PARITY | LED)
  sta PORTA

  ; Initialize output shift register
  lda #%11111111
  sta PORTB
  ; Toggle SOLB low then high to load data to output shift register
  lda #SOLB
  trb PORTA
  tsb PORTA

  ; Default the display bits to 0
  lda #(RW | RS)
  trb PORTA

  jmp program_start

