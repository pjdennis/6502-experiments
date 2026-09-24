buffer_initialize:
  lda #0
  sta BUFFER_READ_POS
  sta BUFFER_WRITE_POS
  sta BUFFER_LOCK
  rts


buffer_lock:
  pha
buffer_lock_retry:
  sei
  lda BUFFER_LOCK
  beq buffer_not_locked
  cli
  bra buffer_lock_retry
buffer_not_locked:
  lda #1
  sta BUFFER_LOCK
  cli
  pla
  rts


buffer_unlock:
  pha
  lda #0
  sta BUFFER_LOCK
  pla
  rts


; On entry A = value to add
buffer_write_to_non_full:
  phx
  ldx BUFFER_WRITE_POS
  sta BUFFER_DATA, X
  inx
  stx BUFFER_WRITE_POS
  plx
  rts


; On exit A = value read
buffer_read_from_non_empty:
  phx
  ldx BUFFER_READ_POS
  lda BUFFER_DATA, X
  inx
  stx BUFFER_READ_POS
  plx
  rts



; Empty: READ_POS == WRITE_POS
buffer_lock_not_empty:
  pha
  phx
buffer_lock_not_empty_wait:
  jsr buffer_lock
  lda BUFFER_WRITE_POS
  cmp BUFFER_READ_POS
  bne buffer_locked_not_empty
  jsr buffer_unlock
  lda #<1
  ldx #>1
  jsr sleep_milliseconds
  bra buffer_lock_not_empty_wait
buffer_locked_not_empty:
  plx
  pla
  rts


; Full:  READ_POS == WRITE_POS + 1
buffer_lock_not_full:
  pha
  phx
buffer_lock_not_full_wait:
  jsr buffer_lock
  lda BUFFER_WRITE_POS
  inc
  cmp BUFFER_READ_POS
  bne buffer_locked_not_full
  jsr buffer_unlock
  lda #<1
  ldx #>1
  jsr sleep_milliseconds
  bra buffer_lock_not_full_wait
buffer_locked_not_full:
  plx
  pla
  rts


buffer_read:
  jsr buffer_lock_not_empty
  jsr buffer_read_from_non_empty
  jsr buffer_unlock
  rts


buffer_write:
  jsr buffer_lock_not_full
  jsr buffer_write_to_non_full
  jsr buffer_unlock
  rts

