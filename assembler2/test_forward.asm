; Test forward reference to non-zero-page label
* = $0200

start
  LDA forward_label    ; Forward ref - will this be 2 or 3 bytes?
  RTS

forward_label = $1234  ; Defined after use, value >= $100

  DATA start
