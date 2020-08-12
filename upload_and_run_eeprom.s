ORIGIN            = $8000
UPLOAD_TO         = $2000

  .include upload_and_run.inc

ready_message: asciiz 'Ready.'

; Vectors
  .org $fffc
  .word program_start
  .word INTERRUPT_ROUTINE
