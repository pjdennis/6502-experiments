; Requires:
;  CONSOLE_WIDTH            - constant - width of console - between 1 and 20
;  CONSOLE_HEIGHT           - constant - height of console between 1 and 4
;  CONSOLE_CHARACTER_COUNT  - 1 byte
;  CONSOLE_TEXT             - buffer for CONSOLE_WIDTH * CONSOLE_HEIGHT bytes

CONSOLE_LENGTH          = CONSOLE_WIDTH * CONSOLE_HEIGHT

ASCII_BACKSPACE          = 0x08

console_offsets:
  .byte DISPLAY_FIRST_LINE
  .byte DISPLAY_SECOND_LINE
  .byte DISPLAY_FIRST_LINE + 20
  .byte DISPLAY_SECOND_LINE + 20


; On exit  A, X, Y are preserved
console_initialize:
  pha
  phx

  stz CONSOLE_CHARACTER_COUNT
  lda #0
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
  cmp #ASCII_BACKSPACE
  beq console_backspace

  phy
  ldy CONSOLE_CHARACTER_COUNT
  sta CONSOLE_TEXT, Y
  inc CONSOLE_CHARACTER_COUNT

  lda CONSOLE_CHARACTER_COUNT
  cmp #CONSOLE_LENGTH
  bne .done

  jsr console_scroll_up

.done
  ply
  rts


; On exit A, X, Y are preserved
console_backspace:
  rts ; TODO - new implementation

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
  phy

  ldx #0
  ldy #0
console_show_loop_lines:
  lda console_offsets, Y
  jsr move_cursor
  phy
  ldy #CONSOLE_WIDTH
console_show_loop_columns:
  lda CONSOLE_TEXT, X
  bne .show_character
  lda #' '
.show_character:
  jsr display_character
  inx
  dey
  bne console_show_loop_columns
  ply
  iny
  cpy #CONSOLE_HEIGHT
  bne console_show_loop_lines

  ply
  plx
  pla
  rts


; Scroll up one line; fill in last line with nulls; adjust character count
; On exit A, X, Y are preserved
console_scroll_up:
  pha
  phx

  ldx #0
.move_loop:
  lda CONSOLE_TEXT + CONSOLE_WIDTH, X
  sta CONSOLE_TEXT, X
  inx
  cpx #(CONSOLE_LENGTH - CONSOLE_WIDTH)
  bne .move_loop
.fill_loop
  stz CONSOLE_TEXT, X
  inx
  cpx #CONSOLE_LENGTH
  bne .fill_loop

  lda CONSOLE_CHARACTER_COUNT
  cmp #CONSOLE_WIDTH
  bcc .done
  sec
  sbc #CONSOLE_WIDTH
  sta CONSOLE_CHARACTER_COUNT

.done:
  plx
  pla
  rts
