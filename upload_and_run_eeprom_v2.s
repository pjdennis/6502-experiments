ORIGIN    = $8000
UPLOAD_TO = $2000

BPS_HUNDREDS = 576 ; 57600 bps

  .include base_config_v2.inc
  .include upload_and_run.inc
  .include initialize_machine_v2.inc
  .include display_routines_8bit.inc

origin_message: asciiz 'ROM'

; Vectors
  .org $fffc
  .word ORIGIN
  .word INTERRUPT_ROUTINE
