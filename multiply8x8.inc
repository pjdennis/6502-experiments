; Multiplies two 8-bit factors to produce a 16-bit product in about 153 cycles.
; On entry A = one factor
;          Y = another factor
; On exit  A = high bits of result
;          MULTIPLY_8X8_RESULT_LOW = low bits of result
;          X is preserved
;          Y and MULTIPLY_8X8_TEMP are not preserved
multiply8x8:
  ; Factor 1 is stored in the lower bits of MULTIPLY_8X8_RESULT_LOW; the low
  ; byte of the product is stored in the upper bits.
  lsr ; prime the carry bit for the loop
  sta MULTIPLY_8X8_RESULT_LOW
  sty MULTIPLY_8X8_TEMP
  lda #0
  ldy #8
.loop:
  ; At the start of the loop, one bit of MULTIPLY_8X8_RESULT_LOW has already
  ; been shifted out into the carry.
  bcc .noadd
  clc
  adc MULTIPLY_8X8_TEMP
.noadd:
  ror
  ror MULTIPLY_8X8_RESULT_LOW  ; pull another bit out for the next iteration
  dey         ; inc/dec don't modify carry; only shifts and adds do
  bne .loop
  rts

