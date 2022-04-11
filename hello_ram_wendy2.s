  .include base_config_wendy2.inc

DISPLAY_STRING_PARAM  = $00 ; 2 bytes

  .org $2000
  jmp program_entry

  .include display_update_routines_4bit.inc
  .include display_string.inc

program_entry:
  jsr clear_display

  lda #<message
  ldx #>message
  jsr display_string

  stp ; Halt the CPU


message: asciiz 'Hello, from ram'
