PORTB  = $F000
PORTA  = $F001
DDRB   = $F002
DDRA   = $F003

  .org $8000

reset:
  lda #%10000000
  sta DDRB

  lda #0

loop:
  eor #%10000000
  sta PORTB
  jsr delay
  bra loop

delay:
  ldx #0
loop2:

  ldy #0
loop3:
  nop
  nop
  nop
  nop
  dey
  bne loop3

  dex
  bne loop2

  rts

  .org $fffc
  .word reset
  .word $0000
 
