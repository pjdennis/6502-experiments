  .org $0000

  lda #0
loop:
  sta counter
  clc
  adc #1
  bra loop

counter:
  .byte $00

  .org $0400
