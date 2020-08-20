; Requires DISPLAY_HEX_INDIRECT_PARAM - 2 bytes for temporary parameter storage

  .include display_hex.inc


; On Entry A, X = Low, High bytes of pointer to 2 byte hex number
display_hex_indirect_16_bits:
  phy
  ldy #2
  jsr display_hex_indirect
  ply
  rts


; On Entry A, X = Low, High bytes of pointer to hex number to display_2_byte_hex
;          Y = number of bytes to display
display_hex_indirect:
  sta DISPLAY_HEX_INDIRECT_PARAM
  stx DISPLAY_HEX_INDIRECT_PARAM + 1
  
display_bytes_hex_loop:
  cpy #0
  beq display_bytes_hex_done
  dey
  lda (DISPLAY_HEX_INDIRECT_PARAM),Y
  jsr display_hex
  bra display_bytes_hex_loop
display_bytes_hex_done:
  rts
