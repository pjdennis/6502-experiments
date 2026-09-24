; pd_char_test_wendy2c.s -- defines a single 5x8 CGRAM glyph that looks
; like "PD" (the original initials from hello.s) and displays it on the
; HD44780 panel.
;
; Loads at $4000 like the other "uploaded payload" demos; the boot ROM
; has already initialised the display, so we can call clear_display and
; the regular helpers directly.

  .include base_config_wendy2c.inc

DISPLAY_STRING_PARAM  = $00 ; 2 bytes

  .org $4000
  jmp program_entry

  .include delay_routines.inc

  .include display_routines_4bit.inc
  .include display_string.inc

program_entry:
  jsr clear_display

  ; Set CGRAM address to slot 0 and stream the 8 rows of the PD glyph.
  ; The HD44780's address counter auto-increments after each data write.
  lda #CMD_SET_CGRAM_ADDRESS
  jsr display_command

  ldx #0
cgram_loop:
  lda pd_glyph,X
  jsr display_character
  inx
  cpx #8
  bne cgram_loop

  ; Park DDRAM address back at the start of line 0.
  lda #CMD_SET_DDRAM_ADDRESS
  jsr display_command

  ; Line 1: "Initials: <PD>"  -- code $08 mirrors CGRAM slot 0.
  lda #<line1
  ldx #>line1
  jsr display_string

  ; Line 2: a row of the same glyph so it's easy to spot.
  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  lda #<line2
  ldx #>line2
  jsr display_string

forever:
  bra forever

line1: .byte "Initials: ", $08, 0
line2: .byte $08, $08, $08, $08, $08, $08, $08, $08, 0


; --- CGRAM bitmap ---
; Single 8-byte 5x8 glyph (the 8th row is the cursor row and is left
; blank). Bit 4 is the leftmost pixel; only the low 5 bits are used.
; Lifted verbatim from hello.s's character_pd.
pd_glyph:
  .byte %11000
  .byte %10100
  .byte %11001
  .byte %10001
  .byte %10011
  .byte %00101
  .byte %00011
  .byte %00000
