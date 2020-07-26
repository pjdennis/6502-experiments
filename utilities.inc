lock_screen:
  sei
  lda SCREEN_LOCK
  beq lock_acquired
  cli
  bra lock_screen
lock_acquired:
  inc SCREEN_LOCK
  cli
  rts


unlock_screen:
  lda #0
  sta SCREEN_LOCK
  rts

; On entry A = byte to display in hex
; On exit  X, Y are preserved
;          A is not preserved
display_hex:
  phx
  jsr convert_to_hex
  jsr display_character
  txa
  jsr display_character
  plx
  rts


delay_tenth:
  pha
  phx

  lda #<100
  ldx #>100
  jsr sleep_milliseconds

  plx
  pla
  rts

