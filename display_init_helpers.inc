  .include display_parameters.inc

reset_and_enable_display_no_cursor:  
  jsr reset_display

  lda #(CMD_ENTRY_MODE_SET | %10)          ; Increment and shift cursor; don't shift display 
  jsr display_command

  lda #(CMD_DISPLAY_ON_OFF_CONTROL | CMD_PARAM_DISPLAY_ON) ; Display on; cursor off; blink off
  jsr display_command

  rts
