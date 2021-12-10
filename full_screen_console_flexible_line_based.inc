; Requires:
;  CONSOLE_WIDTH            - constant - width of console - between 1 and 20
;  CONSOLE_HEIGHT           - constant - height of console between 1 and 4
;  CONSOLE_CHARACTER_COUNT  - 1 byte
;  CONSOLE_TEXT             - buffer for CONSOLE_WIDTH * CONSOLE_HEIGHT bytes

CONSOLE_LENGTH          = CONSOLE_WIDTH * CONSOLE_HEIGHT

ASCII_BACKSPACE          = 0x08
ASCII_NEWLINE            = 0x0a

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
  phx

  cmp #ASCII_BACKSPACE
  beq .console_backspace

  cmp #ASCII_NEWLINE
  beq .console_newline

  ; Handle normal character (not backspace or newline)
  ldx CONSOLE_CHARACTER_COUNT
  sta CONSOLE_TEXT, X
  inc CONSOLE_CHARACTER_COUNT

  lda CONSOLE_CHARACTER_COUNT
  cmp #CONSOLE_LENGTH
  bne .done

  jsr console_scroll_up

.done:
  plx
  rts

  ; Handle backspace
.console_backspace:
  ldx CONSOLE_CHARACTER_COUNT
  beq .done                   ; Already at beginning of buffer
.find_non_zero_loop
  dex
  beq .found_non_zero         ; X == 0 => Reached the beginning of the buffer
  lda CONSOLE_TEXT, X
  beq .find_non_zero_loop     ; Skip over 0 values
.found_non_zero
  lda #0
  sta CONSOLE_TEXT, X
  stx CONSOLE_CHARACTER_COUNT
  bra .done

  ; Handle newline
.console_newline:
  ldx CONSOLE_CHARACTER_COUNT
  sta CONSOLE_TEXT, X

  lda CONSOLE_CHARACTER_COUNT
  cmp #(CONSOLE_LENGTH - CONSOLE_WIDTH)
  bcc .scroll_ok
  jsr console_scroll_up
.scroll_ok:
  lda #CONSOLE_WIDTH
.find_position_loop:
  cmp CONSOLE_CHARACTER_COUNT
  beq .position_not_yet_found
  bcs .position_found
.position_not_yet_found
  clc
  adc #CONSOLE_WIDTH
  bra .find_position_loop
.position_found:
  sta CONSOLE_CHARACTER_COUNT

  bra .done


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
  cpx CONSOLE_CHARACTER_COUNT
  bne .show_normal
  lda #'_'
  bra .show_character
.show_normal:
  lda CONSOLE_TEXT, X
  beq .show_space
  cmp #ASCII_NEWLINE
  bne .show_character
.show_space:
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
