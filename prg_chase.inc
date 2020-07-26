; Chase X back and forth on the screen

run_chase:
  ldy #(DISPLAY_FIRST_LINE + 5)
run_chase_right:
  jsr lock_screen
  tya
  jsr move_cursor
  lda #' '
  jsr display_character
  lda #'X'
  jsr display_character
  jsr unlock_screen

  lda #<150
  ldx #>150
  jsr sleep_milliseconds

  iny
  cpy #(DISPLAY_FIRST_LINE + 10)
  bne run_chase_right

  ldy #(DISPLAY_FIRST_LINE + 9)
run_chase_left:
  jsr lock_screen
  tya
  jsr move_cursor
  lda #'X'
  jsr display_character
  lda #' '
  jsr display_character
  jsr unlock_screen

  lda #<150
  ldx #>150
  jsr sleep_milliseconds

  dey
  cpy #(DISPLAY_FIRST_LINE + 4)
  bne run_chase_left

  bra run_chase
  

