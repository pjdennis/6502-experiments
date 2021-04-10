ORIGIN            = $8000
UPLOAD_TO         = $2000

  .include base_config_v1.inc
  .include upload_and_run.inc
  .include initialize_machine_v1.inc
  .include display_routines_4bit.inc

ready_message: asciiz 'Ready.'

; Vectors
  .org $fffc
  .word program_start
  .word INTERRUPT_ROUTINE
