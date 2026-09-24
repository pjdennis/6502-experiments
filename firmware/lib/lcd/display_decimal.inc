; Requires parameters to be defined - see to_decimal.inc

  .include to_decimal.inc
  .include display_string.inc

; On entry A, X = low, high bytes of value to display
; On exit Y is preserved
;         A, X are not preserved
display_decimal:
  jsr to_decimal
  jmp display_string ; tail call

; On entry A, X = low, high bytes of value to display
;          Y = number of decimal places
; On exit A, X, Y are not preserved
display_decimal_with_places:
  jsr to_decimal_with_places
  jmp display_string ; tail call
