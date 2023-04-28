; Requires DISPLAY_STRING_PARAM - 2 bytes for temporary storage of parameters

; On entry A, X contain low and high bytes of string address
; On exit A, X, Y are preserved
write_string_to_screen:
  pha

  sta DISPLAY_STRING_PARAM
  stx DISPLAY_STRING_PARAM + 1
.print_loop:
  lda (DISPLAY_STRING_PARAM)
  beq .done_printing
  jsr write_character_to_screen
  inc DISPLAY_STRING_PARAM
  bne .print_loop
  inc DISPLAY_STRING_PARAM + 1
  bra .print_loop
.done_printing:

  pla
  rts
