; Requires:
;  CONSOLE_WIDTH            - constant - width of console - between 1 and 20
;  CONSOLE_HEIGHT           - constant - height of console between 1 and 4
;  CONSOLE_CURSOR_POSITION  - 1 byte
;  CONSOLE_TEXT             - buffer for CONSOLE_WIDTH * CONSOLE_HEIGHT bytes

  .include ASCII.inc

CONSOLE_LENGTH           = CONSOLE_WIDTH * CONSOLE_HEIGHT

console_offsets:
  .byte DISPLAY_FIRST_LINE
  .byte DISPLAY_SECOND_LINE
  .byte DISPLAY_FIRST_LINE + 20
  .byte DISPLAY_SECOND_LINE + 20

; On exit  A, X, Y are preserved
console_initialize:
console_clear:
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

  jsr _console_shift

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
  phx
  jsr _console_position_cursor
  plx
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
  cpx #CONSOLE_LENGTH
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


_console_shift:
  pha
  phx
  phy

  ldx #0 ; Pointer into the text
  ldy #0 ; Current line
.loop_lines:
  phy
  ldy #CONSOLE_WIDTH
.loop_characters:
  lda CONSOLE_TEXT, X
  beq .found_end
  inx
  cmp #ASCII_NEWLINE
  beq .line_done
  dey
  bne .loop_characters
.line_done:
  ply
  iny
  bra .loop_lines
.found_end:
  tya
  ply
  cpy #CONSOLE_HEIGHT
  bcc .done
  jsr _console_delete_first_line
.done:
  ply
  plx
  pla
  rts


_console_delete_first_line:
  ldx #0
.find_loop
  lda CONSOLE_TEXT, X
  inx
  cmp #ASCII_NEWLINE
  beq .found
  cpx #CONSOLE_WIDTH
  bne .find_loop
.found:
  cpx CONSOLE_CURSOR_POSITION
  bcc .adjust
  stz CONSOLE_CURSOR_POSITION
  bra .adjusted
.adjust:
  txa
  ; CONSOLE_CURSOR_POSITION <- CONSOLE_CURSOR_POSITION - A
  eor #$ff
  sec
  adc CONSOLE_CURSOR_POSITION
  sta CONSOLE_CURSOR_POSITION
.adjusted:
  ldy #0
.move_loop:
  lda CONSOLE_TEXT, X
  sta CONSOLE_TEXT, Y
  beq .done
  inx
  iny
  bra .move_loop
.done:
  rts


; On exit X, Y contain the console cursor position
;         A is preserved
console_get_cursor_xy:
  pha

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
  tax
  ply

  pla
  rts


; On exit Y is preserved
;         A, X are not preserved
_console_position_cursor:
  phy

  jsr console_get_cursor_xy
  txa
  clc
  adc console_offsets, Y
  jsr move_cursor

  ply
  rts
