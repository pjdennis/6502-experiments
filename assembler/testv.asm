  .org $2000
SUBROUTINE:
  lda $42
  rts

START:
  ldx #0
LOOP:
  inx
  jmp LOOP

  .WORD START
