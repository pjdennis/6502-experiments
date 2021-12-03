  .include display_parameters.inc

  .ifndef DISPLAY_DO_NOT_DISABLE_INTERRUPTS
DISPLAY_DO_NOT_DISABLE_INTERRUPTS = 0
  .endif

reset_display:
  ; TODO - maybe include the full software reset sequence

  lda #(CMD_FUNCTION_SET | %11000) ; Set 8-bit mode; 2-line display; 5x8 font
  jsr display_command

  lda #(CMD_DISPLAY_ON_OFF_CONTROL | %000) ; Display off; cursor off; blink off 
  jsr display_command

  jsr clear_display

  rts


  .include display_update_routines_8bit.inc
  .include display_init_helpers.inc
