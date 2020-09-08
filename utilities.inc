; On exit A, X, Y are preserved
lock_screen:
  pha
lock_screen_retry:
  sei
  lda SCREEN_LOCK
  beq lock_acquired
  cli

  phx
  lda #<0
  ldx #>0
  jsr sleep_milliseconds
  plx

  bra lock_screen_retry
lock_acquired:
  inc SCREEN_LOCK
  cli
  pla
  rts


; On exit A, X, Y are preserved
unlock_screen:
  stz SCREEN_LOCK
  rts


; On exit A, X, Y are preserved
delay_tenth:
  pha
  phx

  lda #<100
  ldx #>100
  jsr sleep_milliseconds

  plx
  pla
  rts
