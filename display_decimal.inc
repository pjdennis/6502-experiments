; Requires parameters to be defined - see to_decimal.inc

  .include to_decimal.inc
  .include display_string.inc

; On entry A, X = low, high bytes of value to display
; On exit Y is preserved
;         A, X are not preserved
display_decimal:
  jsr to_decimal
  jmp display_string ; tail call

