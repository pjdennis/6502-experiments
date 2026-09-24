  .macro invoke_copy_memory,destination,source,source_end
  lda #<(\destination)
  sta CP_M_DEST_P
  lda #>(\destination)
  sta CP_M_DEST_P + 1
  lda #<(\source)
  sta CP_M_SRC_P
  lda #>(\source)
  sta CP_M_SRC_P + 1
  lda #<((\source_end) - (\source))
  sta CP_M_LEN
  lda #>((\source_end) - (\source))
  sta CP_M_LEN + 1
  jsr copy_memory
  .endm


; On entry
;   CP_M_DEST_P - 2 bytes in Zero page containing destination pointer
;   CP_M_SRC_P  - 2 bytes in Zero page containing source pointer
;   CP_M_LEN    - 2 bytes, anywhere, containing source length
; On exit
;   A, X, Y, CP_M_LEN are preserved
;   CP_M_DEST_P and CP_M_SRC_P are not preserved
copy_memory:
  pha
  phx
  phy

  ; Routine adapted from http://6502.org/source/general/memory_move.html
  ; for copying memory (or moving down from a higher to lower address)
  ldy #0
  ldx CP_M_LEN + 1
  beq .remainder
.page_loop:           ; move a page at a time
  lda (CP_M_SRC_P),Y
  sta (CP_M_DEST_P),Y
  iny
  bne .page_loop
  inc CP_M_SRC_P + 1
  inc CP_M_DEST_P + 1
  dex
  bne .page_loop
.remainder:
  ldx CP_M_LEN
.remainder_loop:      ; move the remaining bytes
  lda (CP_M_SRC_P),Y
  sta (CP_M_DEST_P),Y
  iny
  dex
  bne .remainder_loop

;done
  ply
  plx
  pla
  rts

