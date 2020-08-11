; Requires:
;   CP_M_BLOCK_P - 2 bytes in zero page for paramter block pointer
;   CP_M_DEST_P  - 2 bytes in zero page for copy destination pointer
;   CP_M_SRC_P   - 2 bytes in zero page for copy source pointer

CP_M_PARAM_BYTES = 6
CP_M_DEST_OFFSET = 0
CP_M_SRC_OFFSET  = 2
CP_M_LEN_OFFSET  = 4

; Copies memory; supports overlapping ranges when moving from higher to lower address
; On entry paramter block immediately following the jsr call should contain:
;   destination - destination address of the copy (2 bytes)
;   source      - source address of the copy      (2 bytes)
;   length      - number of bytes to copy         (2 bytes)
; On exit
;   A, X, Y are preserved
copy_memory_inline:
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

