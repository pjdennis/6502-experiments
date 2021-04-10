  .include display_parameters.inc

reset_and_enable_display_no_cursor:  
  jsr reset_display

  lda #(CMD_ENTRY_MODE_SET | %10)          ; Increment and shift cursor; don't shift display 
  jsr display_command

  lda #(CMD_DISPLAY_ON_OFF_CONTROL | %100) ; Display on; cursor off; blink off 
  jsr display_command

  rts


; On exit A, X, Y preserved
clear_display:
  pha
  lda #CMD_CLEAR_DISPLAY     ; clear display
  jsr display_command
  pla
  rts


; On entry A = location to move to
; On exit  X, Y preserved
;          A not preserved 
move_cursor:
  ora #CMD_SET_DDRAM_ADDRESS
  jmp display_command        ; tail call

