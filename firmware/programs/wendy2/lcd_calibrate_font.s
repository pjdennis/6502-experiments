; lcd_calibrate_font.s -- display 32 consecutive HD44780 character
; codes for per-LCD font calibration.
;
; A build-time constant FONT_PAGE picks which 32-character page to
; show:
;   FONT_PAGE=0  ->  0x20..0x3F  (space through '?')
;   FONT_PAGE=1  ->  0x40..0x5F  ('@'   through '_')
;   FONT_PAGE=2  ->  0x60..0x7F  ('`'   through DEL)
;
; Line 1 holds the first 16 codes, line 2 the next 16. calibrate.py
; rebuilds-and-uploads this for each page in turn, captures the LCD,
; and records the actual rendered glyph for each code in
; lcd_calibration.json.

  .ifndef FONT_PAGE
FONT_PAGE = 0
  .endif

BASE_CHAR = $20 + FONT_PAGE * 32

  .include base_config_wendy2c.inc

DISPLAY_STRING_PARAM  = $00 ; 2 bytes (display_string scratch)

  .org $4000
  jmp program_entry

  .include delay_routines.inc
  .include display_routines_4bit.inc
  .include display_string.inc

program_entry:
  jsr clear_display

  ; Line 1: write codes BASE_CHAR .. BASE_CHAR+15.
  ldx #0
.line1:
  txa
  clc
  adc #BASE_CHAR
  jsr display_character
  inx
  cpx #16
  bne .line1

  ; Move to line 2.
  lda #(CMD_SET_DDRAM_ADDRESS | DISPLAY_SECOND_LINE)
  jsr display_command

  ; Line 2: codes BASE_CHAR+16 .. BASE_CHAR+31.
  ldx #16
.line2:
  txa
  clc
  adc #BASE_CHAR
  jsr display_character
  inx
  cpx #32
  bne .line2

  stp
