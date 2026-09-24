  .include display_parameters.inc

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


; On exit A, X, Y preserved
display_space:
  pha
  lda #' '
  jsr display_character
  pla
  rts


; On exit A, X, Y preserved
display_cursor_off:
  pha
  lda #(CMD_DISPLAY_ON_OFF_CONTROL | CMD_PARAM_DISPLAY_ON) ; Display on; cursor off
  jsr display_command
  pla
  rts


; On exit A, X, Y preserved
display_cursor_on:
  pha
  lda #(CMD_DISPLAY_ON_OFF_CONTROL | CMD_PARAM_DISPLAY_ON | CMD_PARAM_CURSOR_ON)
  jsr display_command
  pla
  rts
