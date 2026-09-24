ORIGIN    = $2000
UPLOAD_TO = $3000

BPS_HUNDREDS = 1152 ; 115200 bps

  .include base_config_v1.inc
  .include upload_and_run.inc
  .include initialize_machine_v1.inc
  .include display_routines_4bit.inc

origin_message: asciiz 'RAM'
