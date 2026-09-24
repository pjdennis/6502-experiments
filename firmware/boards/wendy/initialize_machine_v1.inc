initialize_machine:

  ; Initialize 6522 port A (memory banking control)
  lda #(BANK_START | SD_CSB)
  sta PORTA
  lda #(BANK_MASK  | SD_CSB)      ; Set pin direction on port A
  sta DDRA

  ; Initialize 6522 port B (display control)
  lda #0
  sta PORTB
  lda #DISPLAY_BITS_MASK | E      ; Set pin direction on port B
  sta DDRB

  jmp program_start
