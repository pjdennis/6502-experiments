; lcd_5x10_demo_wendy2c.s -- HD44780 5x10 dot mode demo.
;
; The wendy2c production wiring uses a 16x2 LCD (5x8 font). 5x10 mode
; is documented in the HD44780 datasheet but is only valid in 1-line
; configurations -- the controller silently downgrades to 5x8 if the
; N bit (2-line) is set. This demo therefore reconfigures the panel
; into 1-line 5x10 mode at boot, paints a sample message that exercises
; descender glyphs (0xE0..0xFF in ROM Code A00) plus a custom 5x10
; CGRAM character with a tall arrow shape, then walks the underline
; cursor across the line so the 10-row cursor placement is visible in
; the live / web LCD render.
;
; Load via demo_wendy2c.sh -- the launcher wires PB6 audio and the
; web UI together, and the LCD render reads font_5x10 from the chip
; state automatically.

  .include base_config_wendy2c.inc

DISPLAY_STRING_PARAM = $00 ; 2 bytes for display_string

  .org $4000
  jmp program_entry

  .include delay_routines.inc
  .include display_routines_4bit.inc
  .include display_string.inc


program_entry:
  ; The standard reset_display puts us in 4-bit, 2-line, 5x8 mode.
  ; Override with our own function-set: DL=0 (4-bit), N=0 (1-line),
  ; F=1 (5x10) -> %00100100 = $24. We also need to redo the cursor /
  ; entry-mode programming since clear_display is unaffected.
  jsr reset_display
  lda #(CMD_FUNCTION_SET | %00100)    ; 4-bit, 1-line, 5x10
  jsr display_command

  ; Load a 5x10 custom glyph into CGRAM slot 0 (11 bytes consumed in
  ; 5x10 mode: 10 dot rows + 1 cursor row). The HD44780 auto-
  ; increments the address counter after each data write.
  lda #CMD_SET_CGRAM_ADDRESS
  jsr display_command
  ldx #0
cgram_loop:
  lda cgram_data,X
  jsr display_character
  inx
  cpx #11
  bne cgram_loop

  ; Park cursor at the start of DDRAM line 0.
  lda #CMD_SET_DDRAM_ADDRESS
  jsr display_command

  ; Print the sample line. The trailing $00 (slot 0 in CGRAM) shows
  ; our 5x10 arrow glyph. Characters $E5 (sigma), $E6 (rho) and $F0
  ; (the "p with macron" / phi descender) all exercise the 5x10
  ; glyph rows beyond the 8-row baseline.
  lda #<msg
  ldx #>msg
  jsr display_string

  ; Turn on display + cursor (underline). cursor visibility is the
  ; whole point of the demo, so leave blink off so the cursor shows
  ; as a continuous underline at row 10.
  lda #(CMD_DISPLAY_ON_OFF_CONTROL | CMD_PARAM_DISPLAY_ON | CMD_PARAM_CURSOR_ON)
  jsr display_command

  ; Walk the cursor left to right across columns 0..15, dwelling a
  ; few hundred ms at each spot. Loops forever so the panel stays
  ; live in the web UI.
walk_loop:
  ldy #0
walk_step:
  tya
  jsr move_cursor
  lda #20                              ; ~200 ms (delay_10_thousandths units)
  jsr delay_10_thousandths
  iny
  cpy #16
  bne walk_step
  ; Done left-to-right; reverse direction so the cursor pings back.
  ldy #15
walk_back:
  tya
  jsr move_cursor
  lda #20
  jsr delay_10_thousandths
  dey
  bpl walk_back
  bra walk_loop


; Sample text. Code $00 in DDRAM picks CGRAM slot 0 (our arrow). The
; high-bit glyphs are ROM Code A00 5x10 chars with descenders. We use
; display_string which is null-terminated, so we substitute $08 (a
; CGRAM alias for slot 0) instead of $00 to avoid the terminator.
msg: .byte "5x10:", $08, " p", $f0, " ", $e5, $e6, "*", 0


; Custom 5x10 glyph for slot 0: an upward-pointing arrow that uses
; the full 10-row height. Bit 4 of each byte is the leftmost pixel.
;
;   . . X . .
;   . X X X .
;   X . X . X
;   . . X . .
;   . . X . .
;   . . X . .
;   . . X . .
;   . . X . .
;   . . X . .
;   . X X X .     (the 11th byte is the cursor row -- left blank)
cgram_data:
  .byte %00000100
  .byte %00001110
  .byte %00010101
  .byte %00000100
  .byte %00000100
  .byte %00000100
  .byte %00000100
  .byte %00000100
  .byte %00000100
  .byte %00001110
  .byte %00000000     ; cursor row
