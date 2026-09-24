ROM_PROGRAM = $a000

  .include base_config_wendy2.inc

  .org $4000
  
  lda #BANK_MASK
  trb BANK_PORT

  jmp ROM_PROGRAM

