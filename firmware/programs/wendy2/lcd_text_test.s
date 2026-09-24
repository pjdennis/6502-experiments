; lcd_text_test.s -- display a fixed 16x2 string for vision-pipeline
; validation. No counters, no toggling -- just the same two lines
; forever.

  .include base_config_wendy2c.inc

DISPLAY_STRING_PARAM  = $00 ; 2 bytes (display_string scratch)

  .org $4000
  jmp program_entry

  .include delay_routines.inc
  .include display_routines_4bit.inc
  .include display_string.inc

program_entry:
  jsr clear_display

  lda #<line1
  ldx #>line1
  jsr display_string

  lda #(CMD_SET_DDRAM_ADDRESS | DISPLAY_SECOND_LINE)
  jsr display_command
  lda #<line2
  ldx #>line2
  jsr display_string

  stp

line1: .byte "Hello, wendy2!  ", 0
line2: .byte "0123456789ABCDEF", 0
