ORIGIN            = $2000
UPLOAD_TO         = $3000

  .include base_config_v2.inc
  .include upload_and_run.inc
  .include initialize_machine_v2.inc
  .include display_routines_8bit.inc

ready_message: asciiz 'Ready (RAM).'
