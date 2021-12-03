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

