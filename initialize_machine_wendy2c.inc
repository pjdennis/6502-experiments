initialize_machine:

  ; Memory Banking
  lda #BANK_MASK
  trb BANK_PORT
  tsb BANK_PORT + DDR_OFFSET


  ; Display
  lda #DISPLAY_BITS_MASK
  trb DISPLAY_DATA_PORT
  tsb DISPLAY_DATA_PORT + DDR_OFFSET

  lda #E
  trb DISPLAY_ENABLE_PORT
  tsb DISPLAY_ENABLE_PORT + DDR_OFFSET

  ; Graphic Display
  lda #GD_CSB | GD_RSTB
  tsb GD_PORT
  tsb GD_PORT + DDR_OFFSET

  jmp program_start
