ORIGIN    = $2000
UPLOAD_TO = $3000

BPS_HUNDREDS = 192 ; 19200 bps

  .include base_config_v2.inc
  .include upload_and_run.inc
  .include initialize_machine_v2.inc
  .include display_routines_8bit.inc

origin_message: asciiz 'RAM'
