; Chase X back and forth on the screen

CHASE_START = DISPLAY_FIRST_LINE + 5
CHASE_WIDTH = DISPLAY_WIDTH - 10

run_chase:
  ldy #CHASE_START
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
  cpy #(CHASE_START + CHASE_WIDTH - 1)
  bne run_chase_right

  ldy #(CHASE_START + CHASE_WIDTH - 2)
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
  cpy #(CHASE_START - 1)
  bne run_chase_left

  bra run_chase
