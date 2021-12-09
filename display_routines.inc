  .ifndef DISPLAY_BITS
DISPLAY_BITS = 0
  .endif

  .if DISPLAY_BITS == 4
  .include display_routines_4bit.inc
DISPLAY_ROUTINES_INCLUDED = 1
  .endif

  .if DISPLAY_BITS == 8
  .include display_routines_8bit.inc
DISPLAY_ROUTINES_INCLUDED = 1
  .endif

  .ifndef DISPLAY_ROUTINES_INCLUDED
  .fail "DISPLAY_BITS must be defined as either 4 or 8. Include the appropriate base_config file."
  .endif
