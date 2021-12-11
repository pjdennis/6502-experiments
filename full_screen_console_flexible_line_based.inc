; Requires:
;  CONSOLE_WIDTH            - constant - width of console - between 1 and 20
;  CONSOLE_HEIGHT           - constant - height of console between 1 and 4
;  CONSOLE_CURSOR_POSITION  - 1 byte
;  CONSOLE_TEXT             - buffer for CONSOLE_WIDTH * CONSOLE_HEIGHT bytes

CONSOLE_LENGTH           = CONSOLE_WIDTH * CONSOLE_HEIGHT

ASCII_BACKSPACE          = 0x08
ASCII_NEWLINE            = 0x0a

console_offsets:
  .byte DISPLAY_FIRST_LINE
  .byte DISPLAY_SECOND_LINE
  .byte DISPLAY_FIRST_LINE + 20
  .byte DISPLAY_SECOND_LINE + 20

; On exit  A, X, Y are preserved
console_initialize:
  stz CONSOLE_CURSOR_POSITION
  stz CONSOLE_TEXT
  rts


; On entry A = character to print
; On exit X, Y are preserved
;         A is not preserved
console_print_character:
  phx
  phy

  cmp #ASCII_BACKSPACE
  beq .console_backspace

  jsr _console_insert

  ldx CONSOLE_CURSOR_POSITION
  ldy CONSOLE_TEXT, X
  bne .store_character
  stz CONSOLE_TEXT + 1, X
.store_character:
  sta CONSOLE_TEXT, X
  inc CONSOLE_CURSOR_POSITION

  lda CONSOLE_CURSOR_POSITION
  cmp #CONSOLE_LENGTH
  bne .done

.done:
  ply
  plx
  rts

  ; Handle backspace
.console_backspace:
  ldx CONSOLE_CURSOR_POSITION
  beq .done                   ; Already at beginning of buffer
.find_non_zero_loop
  dex
  beq .found_non_zero         ; X == 0 => Reached the beginning of the buffer
  lda CONSOLE_TEXT, X
  beq .find_non_zero_loop     ; Skip over 0 values
.found_non_zero
  lda #0
  sta CONSOLE_TEXT, X
  stx CONSOLE_CURSOR_POSITION
  bra .done

  ; Handle newline
.console_newline:
  ldx CONSOLE_CURSOR_POSITION
  sta CONSOLE_TEXT, X

  lda CONSOLE_CURSOR_POSITION
  cmp #(CONSOLE_LENGTH - CONSOLE_WIDTH)
  bcc .scroll_ok
  jsr console_scroll_up
.scroll_ok:
  lda #CONSOLE_WIDTH
.find_position_loop:
  cmp CONSOLE_CURSOR_POSITION
  beq .position_not_yet_found
  bcs .position_found
.position_not_yet_found
  clc
  adc #CONSOLE_WIDTH
  bra .find_position_loop
.position_found:
  sta CONSOLE_CURSOR_POSITION

  bra .done


; On exit A, X, Y are preserved
console_cursor_left:
  pha
  lda CONSOLE_CURSOR_POSITION
  beq .done
  dec CONSOLE_CURSOR_POSITION
  jsr _console_position_cursor
.done:
  pla
  rts


; On exit A, X, Y are preserved
console_cursor_right:
  pha
  phx
  ldx CONSOLE_CURSOR_POSITION
  lda CONSOLE_TEXT, X
  beq .done                    ; At end of displayed text
  inc CONSOLE_CURSOR_POSITION
  jsr _console_position_cursor
.done:
  plx
  pla
  rts


; Show console on screen
; On exit A, X, Y are preserved
console_show:
  pha
  phx
  phy

  jsr display_cursor_off

  ldx #0 ; Pointer into the text
  ldy #0 ; Current line
.loop_lines:
  lda console_offsets, Y
  jsr move_cursor
  phy
  ldy #CONSOLE_WIDTH
.loop_characters:
  lda CONSOLE_TEXT, X
  beq .end_of_text
  inx
  jsr _console_display_character
  cmp #ASCII_NEWLINE
  beq .newline
  dey
  bne .loop_characters
.newline
  ply
  iny
  cpy #CONSOLE_HEIGHT
  bne .loop_lines
  bra .done   ; TODO should never get to here
.end_of_text:
  ply

.done:
  jsr _console_position_cursor
  jsr display_cursor_on

  ply
  plx
  pla
  rts


_console_display_character:
  pha
  cmp #ASCII_NEWLINE
  bne .show
  lda #%10100011   ; looks like newline character
.show:
  jsr display_character
  pla
  rts


_console_insert:
  pha
  phx
  phy

  ldx CONSOLE_CURSOR_POSITION

  lda CONSOLE_TEXT, X
.move_loop:
  beq .done
  inx
  cpx #(CONSOLE_LENGTH - 1)
  beq .truncate
  ldy CONSOLE_TEXT, X
  sta CONSOLE_TEXT, X
  tya
  bra .move_loop
.truncate:
  stz CONSOLE_TEXT, X
.done:
  ply
  plx
  pla
  rts


; On exit Y is preserved
;         A, X are not preserved
_console_position_cursor:
  phy

  ldx #0 ; Pointer into the text
  ldy #0 ; Current line
.loop_lines:
  phy
  ldy #0
.loop_characters:
  cpx CONSOLE_CURSOR_POSITION
  beq .found_cursor
  lda CONSOLE_TEXT, X
  inx
  cmp #ASCII_NEWLINE
  beq .newline
  iny
  cpy #CONSOLE_WIDTH
  bne .loop_characters
.newline
  ply
  iny
  bra .loop_lines
.found_cursor:
  tya
  ply
  clc
  adc console_offsets, Y
  jsr move_cursor

  ply
  rts


; Scroll up one line; fill in last line with nulls; adjust character count
; On exit A, X, Y are preserved
console_scroll_up: ; TODO
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

  lda CONSOLE_CURSOR_POSITION
  cmp #CONSOLE_WIDTH
  bcc .done
  sec
  sbc #CONSOLE_WIDTH
  sta CONSOLE_CURSOR_POSITION

.done:
  plx
  pla
  rts
