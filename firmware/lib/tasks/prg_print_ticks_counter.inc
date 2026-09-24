; Print the scheduler ticks counter

print_ticks_counter:
  jsr lock_screen

  lda #(DISPLAY_SECOND_LINE + 6)
  jsr move_cursor

  sei
  lda TICKS_COUNTER
  pha
  lda TICKS_COUNTER + 1
  cli

  jsr display_hex
  pla
  jsr display_hex

  jsr unlock_screen

  jsr delay_tenth

  bra print_ticks_counter
