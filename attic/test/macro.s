BNE_long: .macro lbl
    beq \@
    jmp \lbl
    \@:
.endmacro


    .org $8000



start:
;  LDA #0
;  BNE_long routine1
;  INC
;  BNE_long routine1

  bra over
  .asciiz "1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890"
over:
  BRK


routine1:
routine2:
