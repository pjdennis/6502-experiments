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
  clc
  lda $104,X          ; Low byte of return address
  sta CP_BLOCK_P
  adc #6              ; This number of bytes of parameters
  sta $104,X
  lda $105,X          ; High byte of return address
  sta CP_BLOCK_P + 1
  adc #0
  sta $105,X

  ldy #(1 + 0)        ; Destination pointer
  lda (CP_BLOCK_P),Y
  sta CP_DEST_P
  iny
  lda (CP_BLOCK_P),Y
  sta CP_DEST_P + 1

  ldy #(1 + 2)        ; Source pointer
  lda (CP_BLOCK_P),Y
  sta CP_SRC_P
  iny
  lda (CP_BLOCK_P),Y
  sta CP_SRC_P + 1

; Routine from http://6502.org/source/general/memory_move.html
  ldy #(1 + 4 + 1)          ; Load length high byte ...
  lda (CP_BLOCK_P),Y
  tax                       ; ... into X
  beq copy_memory_remainder
  ldy #0
copy_memory_page_loop:      ; move a page at a time
  lda (CP_SRC_P),Y
  sta (CP_DEST_P),Y
  iny
  bne copy_memory_page_loop
  inc CP_SRC_P + 1
  inc CP_DEST_P + 1
  dex
  bne copy_memory_page_loop
copy_memory_remainder:
  ldy #(1 + 4)              ; Load length low byte ...
  lda (CP_BLOCK_P),Y
  tax                       ; ... into X
  beq copy_memory_done
  ldy #0
copy_memory_remainder_loop: ; move the remaining bytes
  lda (CP_SRC_P),Y
  sta (CP_DEST_P),Y
  iny
  dex
  bne copy_memory_remainder_loop

copy_memory_done:
  ply
  plx
  pla
  rts
