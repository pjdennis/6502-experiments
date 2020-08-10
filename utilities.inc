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


CP_M_PARAM_BYTES = 6
CP_M_DEST_OFFSET = 0
CP_M_SRC_OFFSET  = 2
CP_M_LEN_OFFSET  = 4

; On entry return address location contains destination, source, length
; On exit  A, X, Y are preserved
copy_memory:
  pha
  phx
  phy

  ; Read parameter block location (minus one) into CP_M_BLOCK_P and fix up the return address
  tsx
  clc
  lda $104,X                  ; Low byte of return address
  sta CP_M_BLOCK_P
  adc #CP_M_PARAM_BYTES       ; This number of bytes of parameters
  sta $104,X
  lda $105,X                  ; High byte of return address
  sta CP_M_BLOCK_P + 1
  adc #0
  sta $105,X

  ; Read parameter values
  ldy #(1 + CP_M_DEST_OFFSET) ; Destination pointer
  lda (CP_M_BLOCK_P),Y
  sta CP_M_DEST_P
  iny
  lda (CP_M_BLOCK_P),Y
  sta CP_M_DEST_P + 1

  ldy #(1 + CP_M_SRC_OFFSET)  ; Source pointer
  lda (CP_M_BLOCK_P),Y
  sta CP_M_SRC_P
  iny
  lda (CP_M_BLOCK_P),Y
  sta CP_M_SRC_P + 1

  ; Routine adapted from http://6502.org/source/general/memory_move.html
  ; for copying memory (or moving down from a higher to lower address)
  ldy #(1 + CP_M_LEN_OFFSET + 1) ; Load length high byte ...
  lda (CP_M_BLOCK_P),Y
  tax                            ; ... into X
  beq copy_memory_remainder
  ldy #0
copy_memory_page_loop:           ; move a page at a time
  lda (CP_M_SRC_P),Y
  sta (CP_M_DEST_P),Y
  iny
  bne copy_memory_page_loop
  inc CP_M_SRC_P + 1
  inc CP_M_DEST_P + 1
  dex
  bne copy_memory_page_loop
copy_memory_remainder:
  ldy #(1 + CP_M_LEN_OFFSET)     ; Load length low byte ...
  lda (CP_M_BLOCK_P),Y
  tax                            ; ... into X
  beq copy_memory_done
  ldy #0
copy_memory_remainder_loop:      ; move the remaining bytes
  lda (CP_M_SRC_P),Y
  sta (CP_M_DEST_P),Y
  iny
  dex
  bne copy_memory_remainder_loop

copy_memory_done:
  ply
  plx
  pla
  rts
