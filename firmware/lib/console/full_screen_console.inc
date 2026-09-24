; Requires:
;  CONSOLE_CHARACTER_COUNT  - 1 byte
;  CONSOLE_TEXT             - buffer for CONSOLE_LENGTH bytes

CONSOLE_LENGTH          = 32

; On exit  A, X, Y are preserved
console_initialize:
  pha
  phx

  stz CONSOLE_CHARACTER_COUNT
  lda #' '
  ldx #0
console_initialize_loop:
  sta CONSOLE_TEXT, X
  inx
  cpx #CONSOLE_LENGTH
  bne console_initialize_loop

  plx
  pla
  rts


; On entry A = character to print
; On exit X, Y are preserved
;         A is not preserved
console_print_character:
  phx
  phy
  tax

  lda CONSOLE_CHARACTER_COUNT
  cmp #CONSOLE_LENGTH
  bne console_print_add_character

  dec CONSOLE_CHARACTER_COUNT
  ldy #0
console_copy_loop:
  iny
  cpy #CONSOLE_LENGTH
  beq console_print_add_character

  lda CONSOLE_TEXT, Y
  sta CONSOLE_TEXT - 1, Y
  bra console_copy_loop
console_print_add_character:
  ldy CONSOLE_CHARACTER_COUNT
  txa
  sta CONSOLE_TEXT, Y
  iny
  sty CONSOLE_CHARACTER_COUNT

  ply
  plx
  rts


; On exit A, X, Y are preserved
console_backspace:
  pha
  phy
  ldy CONSOLE_CHARACTER_COUNT
  beq console_backspace_done
  dey
  lda #' '
  sta CONSOLE_TEXT, Y
  sty CONSOLE_CHARACTER_COUNT
console_backspace_done:
  ply
  pla
  rts


; Show console on screen
; On exit A, X, Y are preserved
console_show:
  pha
  phx

  lda #DISPLAY_FIRST_LINE
  jsr move_cursor
  ldx #0
console_show_loop_1:
  lda CONSOLE_TEXT, X
  jsr display_character
  inx
  cpx #(CONSOLE_LENGTH / 2)
  bne console_show_loop_1

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
console_show_loop_2:
  lda CONSOLE_TEXT, X
  jsr display_character
  inx
  cpx #CONSOLE_LENGTH
  bne console_show_loop_2

  plx
  pla
  rts
