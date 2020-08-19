; Requires DISPLAY_STRING_PARAM - 2 bytes for temporary storage of parameters

  .include display_update_routines.inc

; On entry A, X contain low and high bytes of string address
; On exit A, X, Y are preserved
display_string:
  pha
  phx
  phy

  sta DISPLAY_STRING_PARAM
  stx DISPLAY_STRING_PARAM + 1
  ldy #0
print_loop:
  lda (DISPLAY_STRING_PARAM),Y
  beq done_printing
  jsr display_character
  iny
  jmp print_loop
done_printing:

  ply
  plx
  pla
  rts
