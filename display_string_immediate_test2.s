  .include base_config_v1.inc

D_S_I_P = $00 ; 2 bytes

  .org $2000
  jmp program_entry

  .include display_update_routines.inc
  .include display_string_immediate.inc

program_entry:
  jsr display_string_immediate
  .asciiz "Hello, "

  jsr display_string_immediate
  .asciiz "world!"
  
wait:
  wai
  bra wait
