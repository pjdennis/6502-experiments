; lcd_calibrate_font_5x10.s -- display 16 consecutive char codes in
; 5x10 single-line mode for per-LCD 5x10 font calibration.
;
; A build-time constant FONT_PAGE_5X10 picks which 16-character page:
;   FONT_PAGE_5X10=0  ->  0xE0..0xEF
;   FONT_PAGE_5X10=1  ->  0xF0..0xFF
;
; In 5x10 single-line mode the panel is 16 chars wide x 1 char tall,
; where each char is 5 dots wide x 10 dots tall. The 8 top dot rows
; occupy the physical "row 0" cells; the 2 bottom dot rows spill into
; the top 2 dot rows of the physical "row 1" cells.

  .ifndef FONT_PAGE_5X10
FONT_PAGE_5X10 = 0
  .endif

BASE_CHAR_5X10 = $E0 + FONT_PAGE_5X10 * 16

  .include base_config_wendy2c.inc

DISPLAY_STRING_PARAM  = $00 ; 2 bytes (display_string scratch)

  .org $4000
  jmp program_entry

  .include delay_routines.inc
  .include display_routines_4bit.inc
  .include display_string.inc

program_entry:
  ; reset_display puts the panel in 4-bit / 2-line / 5x8. Override
  ; with our own function-set: DL=0 (4-bit), N=0 (1-line), F=1 (5x10).
  ; The HD44780 silently downgrades F to 5x8 in 2-line mode, so the
  ; N=0 reconfiguration is required.
  jsr reset_display

  ; If the panel was already in 5x10 mode from a previous run, the
  ; reset_display sequence above doesn't always fully bring it back
  ; into 2-line/5x8 -- run it a second time to be sure.
  jsr reset_display

  lda #(CMD_FUNCTION_SET | %00100)
  jsr display_command

  ; CGRAM access + a leading low-bit DDRAM write are REQUIRED on this
  ; panel before any high-bit ROM glyphs ($E0..$FF) will render in
  ; 5x10 mode -- without that priming, the entire row stays blank.
  ; Load 11 zero bytes into CGRAM slot 0 so the panel state is sane.
  lda #CMD_SET_CGRAM_ADDRESS
  jsr display_command
  ldx #0
.cgram_init:
  lda #0
  jsr display_character
  inx
  cpx #11
  bne .cgram_init

  ; Fill DDRAM with spaces (low-bit chars) first, then back up and
  ; overwrite with the high-bit target codes. The full-row low-bit
  ; pre-write is needed to wake up the 5x10 ROM lookup for high-bit
  ; codes -- a single priming write isn't reliably enough.
  lda #CMD_SET_DDRAM_ADDRESS
  jsr display_command
  ldx #0
.prime:
  lda #' '
  jsr display_character
  inx
  cpx #16
  bne .prime

  lda #CMD_SET_DDRAM_ADDRESS
  jsr display_command
  ldx #0
.loop:
  txa
  clc
  adc #BASE_CHAR_5X10
  jsr display_character
  inx
  cpx #16
  bne .loop

  ; reset_display left the panel off; turn it back on so the capture
  ; sees the rendered glyphs.
  lda #(CMD_DISPLAY_ON_OFF_CONTROL | CMD_PARAM_DISPLAY_ON)
  jsr display_command

  stp
