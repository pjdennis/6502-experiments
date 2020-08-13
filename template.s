  .include base_config_v1.inc

  .org $2000
  jmp program_entry

  .include display_update_routines.inc

program_entry:
; Program code goes here
  
wait:
  bra wait

