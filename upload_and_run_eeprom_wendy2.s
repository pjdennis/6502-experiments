ORIGIN    = $8000
UPLOAD_TO = $4000

BPS_HUNDREDS = 384 ; 38400 bps

  .include base_config_wendy2.inc
  .include upload_and_run.inc
  .include initialize_machine_wendy2.inc
  .include display_routines_4bit.inc

ready_message: asciiz 'Ready.'

; Vectors
  .org $fffc
  .word ORIGIN
  .word INTERRUPT_ROUTINE
