; Requires TO_DECIMAL_PARAM (9 bytes)

TO_DECIMAL_VALUE = TO_DECIMAL_PARAM + 0  ; 2 bytes
TO_DECIMAL_MOD10 = TO_DECIMAL_PARAM + 2  ; 1 byte
TO_DECIMAL_RESULT = TO_DECIMAL_MOD10 + 1 ; 6 bytes

; On entry A,X = low, high bytes of value to convert
; On exit TO_DECIMAL_RESULT contains the result string
;         Y is preserved
;         A,X point to the result
to_decimal:
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
  ldx #8
to_decimal_shift_loop:
  lda TO_DECIMAL_RESULT-1,X
  sta TO_DECIMAL_RESULT,X
  dex
  bne to_decimal_shift_loop

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
