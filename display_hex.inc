  .include convert_to_hex.inc

; On entry A = byte to display in hex
; On exit  A, X, Y are preserved
display_hex:
  pha
  phx
  jsr convert_to_hex
  jsr display_character
  txa
  jsr display_character
  plx
  pla
  rts
