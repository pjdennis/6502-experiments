;On entry: 

CONSOLE_POSITION        = $0000
CONSOLE_LENGTH          = $0001
CONSOLE_CHARACTER_COUNT = $0002

CONSOLE_TEXT            = $0200

; On entry A = position on screen
;          X = length
; On exit  X, Y are preserved
;          A is not preserved
console_initialize:
  sta CONSOLE_POSITION
  stx CONSOLE_LENGTH
  lda #0
  sta CONSOLE_CHARACTER_COUNT

  rts


; On entry A = character to print
; On exit X, Y are preserved
;         A is not preserved
console_print_character:
  phx
  phy
  tax

  lda CONSOLE_CHARACTER_COUNT
  cmp CONSOLE_LENGTH
  bne console_print_add_character

  dec CONSOLE_CHARACTER_COUNT
  ldy #0
console_copy_loop:
  iny
  cpy CONSOLE_LENGTH
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


; Show console on screen
; On exit A, X, Y are preserved
console_show:
  pha
  phx

  jsr lock_screen

  lda CONSOLE_POSITION
  jsr move_cursor

  ldx #0
console_show_loop:
  cpx CONSOLE_CHARACTER_COUNT
  beq console_clear_loop
  lda CONSOLE_TEXT, X
  jsr display_character
  inx
  bra console_show_loop
console_clear_loop:
  cpx CONSOLE_LENGTH
  beq console_show_done
  lda #' '
  jsr display_character
  inx
  bra console_clear_loop
console_show_done:
  jsr unlock_screen

  plx
  pla
  rts

