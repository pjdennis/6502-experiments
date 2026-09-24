; lcd_calibrate.s -- Display an all-on 5x8 block in every LCD cell.
;
; Used by the vision pipeline (lcd_ocr.py --calibrate) to locate cell
; boundaries and pixel grid: with all 32 cells lit identically, the
; per-cell bright rectangles in the captured image directly give the
; cell centres, and the inter-cell gaps reveal the LCD's actual pixel
; pitch.
;
; CGRAM slot 0 (= DDRAM byte $00 or $08) is loaded with %11111 on every
; one of the 8 rows. The whole DDRAM is then filled with $00, so every
; visible cell renders the same fully-lit block.

  .include base_config_wendy2c.inc

DISPLAY_STRING_PARAM  = $00 ; 2 bytes (display_string scratch)

  .org $4000
  jmp program_entry

  .include delay_routines.inc
  .include display_routines_4bit.inc
  .include display_string.inc

program_entry:
  jsr clear_display

  ; Stream the 8 rows of CGRAM slot 0 (all bits = 1 across the 5 dot
  ; columns). The address counter auto-increments after each byte.
  lda #CMD_SET_CGRAM_ADDRESS
  jsr display_command
  ldx #0
.cgram_loop:
  lda #%00011111
  jsr display_character
  inx
  cpx #8
  bne .cgram_loop

  ; Park DDRAM at line 1, column 0 then fill 16 cells with code $00.
  lda #CMD_SET_DDRAM_ADDRESS
  jsr display_command
  ldx #0
.line1_loop:
  lda #0
  jsr display_character
  inx
  cpx #16
  bne .line1_loop

  ; Move to line 2 and fill another 16 cells.
  lda #(CMD_SET_DDRAM_ADDRESS | DISPLAY_SECOND_LINE)
  jsr display_command
  ldx #0
.line2_loop:
  lda #0
  jsr display_character
  inx
  cpx #16
  bne .line2_loop

  stp
