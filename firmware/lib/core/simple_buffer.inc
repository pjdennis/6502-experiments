; Requires
;   SIMPLE_BUFFER_WRITE_PTR - 1 byte
;   SIMPLE_BUFFER_READ_PTR  - 1 byte
;   SIMPLE_BUFFER           - 256 bytes

; On exit A, X, Y are preserved
simple_buffer_initialize:
  stz SIMPLE_BUFFER_WRITE_PTR
  stz SIMPLE_BUFFER_READ_PTR
  rts


; On entry A = byte to write
; On exit A, X, Y are preserved
;         C = Set if buffer full
simple_buffer_write:
  phx
  ldx SIMPLE_BUFFER_WRITE_PTR  
  inx
  cpx SIMPLE_BUFFER_READ_PTR
  beq simple_buffer_write_full
  dex
  sta SIMPLE_BUFFER, X
  inx
  stx SIMPLE_BUFFER_WRITE_PTR
  clc
  bra simple_buffer_write_done
simple_buffer_write_full:
  sec
simple_buffer_write_done:
  plx
  rts


; On exit A = value from buffer
;         C = Set if buffer is empty
;         X, Y are preserved
simple_buffer_read:
  phx
  ldx SIMPLE_BUFFER_READ_PTR
  cpx SIMPLE_BUFFER_WRITE_PTR
  beq simple_buffer_read_empty
  lda SIMPLE_BUFFER, X
  inx
  stx SIMPLE_BUFFER_READ_PTR
  clc
  bra simple_buffer_read_done
simple_buffer_read_empty:
  sec 
simple_buffer_read_done:
  plx
  rts 

