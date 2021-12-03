  .include base_config_v1.inc

DISPLAY_STRING_PARAM  = $00 ; 2 bytes
TO_DECIMAL_PARAM      = $02 ; 9 bytes

  .org $2000
  jmp program_entry

  .include display_update_routines_4bit.inc
  .include to_decimal.inc
  .include display_string.inc

test_number = 1357

program_entry:

  lda #<test_number
  ldx #>test_number
  jsr to_decimal
  jsr display_string

  stp ; Halt the CPU
