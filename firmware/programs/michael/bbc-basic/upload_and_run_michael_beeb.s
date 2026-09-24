ORIGIN    = $C000
UPLOAD_TO = $0900

INTERRUPT_ROUTINE = $0800 ; Possibly could place at $0300

BPS_HUNDREDS = 576 ; 57600 bps

  .include ../BeebEater/BeebDefinitions.inc

  .org BASIC
  .incbin ../BeebEater/Basic4r32.rom

  .include base_config_v2.inc
  .include upload_and_run.inc
  .include initialize_machine_v2.inc
  .include display_routines_8bit.inc

origin_message: asciiz 'BBC'

code_interrupt = INTERRUPT_ROUTINE
reset          = ORIGIN

  .include ../BeebEater/BeebEntryPoints.inc
