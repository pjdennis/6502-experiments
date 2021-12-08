; Chase X back and forth on the screen

CHASE_START = DISPLAY_FIRST_LINE + 5
CHASE_WIDTH = DISPLAY_WIDTH - 10
CHASE_DELAY = 200

;previous pos in X
;current pos in Y

run_chase:
  jsr lock_screen
  lda #CHASE_START
  jsr move_cursor
  lda #'X'
  jsr display_character
  jsr unlock_screen

run_chase_loop:
  ldy #CHASE_START + 1

run_chase_right:
  lda #<CHASE_DELAY
  ldx #>CHASE_DELAY
  jsr sleep_milliseconds

  jsr lock_screen
  tya
  jsr move_cursor
  lda #'X'
  jsr display_character
  dey
  tya
  jsr move_cursor
  lda #' '
  jsr display_character
  jsr unlock_screen

  iny
  iny
  cpy #(CHASE_START + CHASE_WIDTH)
  bne run_chase_right

  ldy #(CHASE_START + CHASE_WIDTH - 2)
run_chase_left:
  lda #<CHASE_DELAY
  ldx #>CHASE_DELAY
  jsr sleep_milliseconds

  jsr lock_screen
  tya
  jsr move_cursor
  lda #'X'
  jsr display_character
  lda #' '
  jsr display_character
  jsr unlock_screen

  dey
  cpy #(CHASE_START - 1)
  bne run_chase_left

  bra run_chase_loop
