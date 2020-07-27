  .org $8000
  .word 0404

  .section first_section

  .org $4000
start:
  .word 0303
  jmp start


  .org $fffc
  .word $0101
  .word $0202
