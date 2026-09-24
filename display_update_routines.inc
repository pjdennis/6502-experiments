; Provides the following:
;   display_command    - sends a command (A) to the display
;   display_character  - sends a character (A) to the display, with extended characters if enabled
;   display_data       - sends data (A) to the display without translation for extended characters
;   clear_display      - clears the display
;   move_cursor        - moves cursor (to A)
;   display_space      - displays a space
;   display_cursor_off - turns off the cursor
;   display_cursor_on  - turns on the cursor

  .ifndef DISPLAY_BITS
DISPLAY_BITS = 0
  .endif

  .if DISPLAY_BITS == 4
  .include display_update_routines_4bit.inc
DISPLAY_ROUTINES_INCLUDED = 1
  .endif

  .if DISPLAY_BITS == 8
  .include display_update_routines_8bit.inc
DISPLAY_ROUTINES_INCLUDED = 1
  .endif

  .ifndef DISPLAY_ROUTINES_INCLUDED
  .fail "DISPLAY_BITS must be defined as either 4 or 8. Include the appropriate base_config file."
  .endif

