  .org $fc00

table:
  .byte $12, $34, $56, $78, $9a, $bc, $de, $f1, $12, $34, $56, $78, $9a, $bc, $de, $f1 
  .byte $12, $34, $56, $78, $9a, $bc, $de, $f1, $12, $34, $56, $78, $9a, $bc, $de, $f1 
  .byte $12, $34, $56, $78, $9a, $bc, $de, $f1, $12, $34, $56, $78, $9a, $bc, $de, $f1 
  .byte $12, $34, $56, $78, $9a, $bc, $de, $f1, $12, $34, $56, $78, $9a, $bc, $de, $f1 
  .byte $12, $34, $56, $78, $9a, $bc, $de, $f1, $12, $34, $56, $78, $9a, $bc, $de, $f1 
  .byte $12, $34, $56, $78, $9a, $bc, $de, $f1, $12, $34, $56, $78, $9a, $bc, $de, $f1 
  .byte $12, $34, $56, $78, $9a, $bc, $de, $f1, $12, $34, $56, $78, $9a, $bc, $de, $f1 
  .byte $12, $34, $56, $78, $9a, $bc, $de, $f1, $12, $34, $56, $78, $9a, $bc, $de, $f1 
  .byte $12, $34, $56, $78, $9a, $bc, $de, $f1, $12, $34, $56, $78, $9a, $bc, $de, $f1 
  .byte $12, $34, $56, $78, $9a, $bc, $de, $f1, $12, $34, $56, $78, $9a, $bc, $de, $f1 
  .byte $12, $34, $56, $78, $9a, $bc, $de, $f1, $12, $34, $56, $78, $9a, $bc, $de, $f1 
  .byte $12, $34, $56, $78, $9a, $bc, $de, $f1, $12, $34, $56, $78, $9a, $bc, $de, $f1 
  .byte $12, $34, $56, $78, $9a, $bc, $de, $f1, $12, $34, $56, $78, $9a, $bc, $de, $f1 
  .byte $12, $34, $56, $78, $9a, $bc, $de, $f1, $12, $34, $56, $78, $9a, $bc, $de, $f1 
  .byte $12, $34, $56, $78, $9a, $bc, $de, $f1, $12, $34, $56, $78, $9a, $bc, $de, $f1 
  .byte $12, $34, $56, $78, $9a, $bc, $de, $f1, $12, $34, $56, $78, $9a, $bc, $de, $f1 
placeholder:
  .byte $00

reset:
  ldy #$f0
  ldx #0
  lda #0

loop1:
  clc
  adc table,X
  inx
  bne loop1
  clc
  adc #$E0
  iny
  bne loop1

  tax
loop2:
  lda $8000,X
  bra loop2

  .org $fffc
  .word reset
  .word $0000
