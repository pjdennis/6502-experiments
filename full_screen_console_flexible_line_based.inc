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
  dec CONSOLE_CURSOR_POSITION
.backspace_loop:
  lda CONSOLE_TEXT, X
  sta CONSOLE_TEXT - 1, X
  beq .done
  inx
  bra .backspace_loop


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
  beq .loop_blank_characters   ; Done with data; fill in rest with blanks
  inx
  cmp #ASCII_NEWLINE
  beq .newline
  jsr display_character
  dey
  bne .loop_characters
  bra .line_done
.newline:
  lda #%10100011
  jsr display_character
.newline_loop:
  dey
  beq .line_done
  lda #' '
  jsr display_character
  bra .newline_loop
.line_done:
  ply
  iny
  cpy #CONSOLE_HEIGHT
  bne .loop_lines
  bra .done   ; TODO should never get to here

.loop_blank_lines:
  lda console_offsets, Y
  jsr move_cursor
  phy
  ldy #CONSOLE_WIDTH
.loop_blank_characters:
  lda #' '
  jsr display_character
  dey
  bne .loop_blank_characters
  ply
  iny
  cpy #CONSOLE_HEIGHT
  bne .loop_blank_lines

.done:
  jsr _console_position_cursor
  jsr display_cursor_on

  ply
  plx
  pla
  rts


_console_insert:
  pha
  phx
  phy

  ldx CONSOLE_CURSOR_POSITION
  lda CONSOLE_TEXT, X
  beq .done
.move_loop:
  inx
  cpx #(CONSOLE_LENGTH - 1)
  beq .terminate
  ldy CONSOLE_TEXT, X
  sta CONSOLE_TEXT, X
  tya
  bne .move_loop
  inx
.terminate:
  stz CONSOLE_TEXT, X
.done
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
