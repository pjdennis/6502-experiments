SUBROUTINE
  LDAZ $42
  RTS

START ; This is a comment
  LDX# $00 ; another comment
LOOP
  INX ; and a comment
  JMP LOOP

  WORD START
