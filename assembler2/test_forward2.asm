; Test forward reference - if sizes differ between passes,
; after_lda will be at wrong address
* = $0200

start
  LDA forward_label    ; Forward ref - 2 or 3 bytes?
after_lda
  LDA #$42             ; This should be at $0205 if LDA above is 3 bytes
  RTS

forward_label = $1234  ; Defined after use, value >= $100

; These should show the addresses
  DATA after_lda       ; Should be $0205
  DATA start           ; Should be $0200
