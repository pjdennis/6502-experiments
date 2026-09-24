; Requires TO_DECIMAL_PARAM (10 bytes)

TO_DECIMAL_VALUE  = TO_DECIMAL_PARAM + 0 ; 2 bytes
TO_DECIMAL_MOD10  = TO_DECIMAL_PARAM + 2 ; 1 byte
TO_DECIMAL_RESULT = TO_DECIMAL_PARAM + 3 ; 7 bytes

TO_DECIMAL_PARAM_STOP = TO_DECIMAL_PARAM + 10

TO_DECIMAL_NO_DECIMAL_PLACES = 128

; On entry A, X = low, high bytes of value to convert
; On exit A, X point to the result
;         Y is preserved
to_decimal:
  phy
  ldy #0
  jsr to_decimal_with_places
  ply
  rts


; On entry A, X = low, high bytes of value to convert
;          Y = number of decimal places
; On exit A, X point to the result
;         Y is not preserved
; Warning: does not support values < 1 (decimal point won't display)
to_decimal_with_places:
  cpy #0
  bne to_decimal_initialize
  ldy #TO_DECIMAL_NO_DECIMAL_PLACES

to_decimal_initialize:
  ; Initialize result to empty string
  stz TO_DECIMAL_RESULT
  
  ; Initialize value to be the number to convert
  sta TO_DECIMAL_VALUE
  stx TO_DECIMAL_VALUE + 1

to_decimal_divide:
  ; Initialize the remainder to be zero
  stz TO_DECIMAL_MOD10
  clc

  ldx #16
to_decimal_divloop:
  ; Rotate quotient and remainder
  rol TO_DECIMAL_VALUE
  rol TO_DECIMAL_VALUE + 1
  rol TO_DECIMAL_MOD10

  ; a = dividend - divisor
  sec
  lda TO_DECIMAL_MOD10
  sbc #10
  bcc to_decimal_ignore_result ; Branch if dividend < divisor
  sta TO_DECIMAL_MOD10

to_decimal_ignore_result:
  dex
  bne to_decimal_divloop
  rol TO_DECIMAL_VALUE
  rol TO_DECIMAL_VALUE + 1

  ; Shift result
to_decimal_shift:
  ldx #5
  cpy #TO_DECIMAL_NO_DECIMAL_PLACES
  beq to_decimal_shift_loop
  inx
to_decimal_shift_loop:
  lda TO_DECIMAL_RESULT-1,X
  sta TO_DECIMAL_RESULT,X
  dex
  bne to_decimal_shift_loop

  cpy #0
  bne to_decimal_save_result
  lda #'.'
  sta TO_DECIMAL_RESULT
  dey
  bra to_decimal_shift

to_decimal_save_result:
  cpy #TO_DECIMAL_NO_DECIMAL_PLACES
  beq to_decimal_save_result_2
  dey
to_decimal_save_result_2
  ; Save value into result
  lda TO_DECIMAL_MOD10
  clc
  adc #'0'
  sta TO_DECIMAL_RESULT

  ; If value != 0 then continue dividing
  lda TO_DECIMAL_VALUE
  ora TO_DECIMAL_VALUE + 1
  bne to_decimal_divide

  lda #<TO_DECIMAL_RESULT
  ldx #>TO_DECIMAL_RESULT

  rts
