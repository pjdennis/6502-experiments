  .include base_config_v1.inc

D_S_I_P = $00 ; 2 bytes

  .org $2000
  jmp program_entry

  .include display_string_immediate.inc

program_entry:

  jsr display_string_immediate
  .asciiz 'Testing speeds'

loop:
  lda $00
  lda $3fff
  lda $6000
  lda $8000
  bra loop
