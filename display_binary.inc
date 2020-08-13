; On entry A contains the value to display in binary
; On exit  A, X, Y are preserved
display_binary:
  pha
  phx
  phy

  ldx #8
display_binary_loop:
  asl
  tay
  bcs display_binary_one
; binary 0
  lda #'0'
  bra display_binary_continue
display_binary_one:
  lda #'1'
display_binary_continue:
  jsr display_character
  tya
  dex
  bne display_binary_loop

  ply
  plx
  pla
  rts
