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


delay_tenth:
  pha
  phx

  lda #<100
  ldx #>100
  jsr sleep_milliseconds

  plx
  pla
  rts


; On entry return address location contains destination, source, length
; On exit  A, X, Y are preserved
copy_memory:
  pha
  phx
  phy

  tsx
  lda $104,X       ; low byte of return address
  sta CP_BLOCK_P
  lda $105,X       ; high byte of return address
  sta CP_BLOCK_P + 1

  ldy #1

  lda (CP_BLOCK_P),Y
  sta CP_DEST_P
  iny
  lda (CP_BLOCK_P),Y
  sta CP_DEST_P + 1
  iny

  lda (CP_BLOCK_P),Y
  sta CP_SRC_P
  iny
  lda (CP_BLOCK_P),Y
  sta CP_SRC_P + 1
  iny

  lda (CP_BLOCK_P),Y
  sta CP_LEN
  iny
  lda (CP_BLOCK_P),Y
  sta CP_LEN + 1

  tya
  clc
  adc CP_BLOCK_P
  sta $104,X
  lda #0
  adc CP_BLOCK_P + 1
  sta $105,X

copy_memory_loop:
  ; Check for CP_LEN decremented to zero
  lda CP_LEN
  bne copy_memory_still_going
  lda CP_LEN + 1
  beq copy_memory_done
copy_memory_still_going:

  ; Copy the byte
  lda (CP_SRC_P)
  sta (CP_DEST_P)

  ; Increment source pointer
  inc CP_SRC_P
  bne copy_memory_src_p_high_correct
  inc CP_SRC_P + 1
copy_memory_src_p_high_correct:

  ; Increment destination pointer
  inc CP_DEST_P
  bne copy_memory_dest_p_high_correct
  inc CP_DEST_P + 1
copy_memory_dest_p_high_correct:

  ; Decrement the length
  lda CP_LEN
  bne copy_memory_high_correct
  dec CP_LEN + 1
copy_memory_high_correct:
  dec CP_LEN
  bra copy_memory_loop

copy_memory_done:

  ply
  plx
  pla
  rts
