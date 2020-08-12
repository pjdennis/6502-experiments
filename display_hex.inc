; On entry A = byte to display in hex
; On exit  X, Y are preserved
;          A is not preserved
display_hex:
  phx
  jsr convert_to_hex
  jsr display_character
  txa
  jsr display_character
  plx
  rts
