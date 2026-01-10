filename
  .data "test.txt" $00

start2
  LDA #'X'
  JSR write_d
  JMP start

  .data start2
