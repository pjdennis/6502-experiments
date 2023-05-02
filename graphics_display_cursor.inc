; Requires
;   GDC_ZERO_PAGE_BASE
;   GDC_CHAR_BUFFER - buffer will store GD_CHAR_ROWS * GD_CHAR_COLS screen characters
;   graphics_display.inc
;   multiply8x8.inc

GDC_CHAR_PTR       = GDC_ZERO_PAGE_BASE + $00 ; 2 bytes

GDC_ZERO_PAGE_STOP = GDC_ZERO_PAGE_BASE + $02

GDC_CHAR_BUFFER_STOP = GDC_CHAR_BUFFER + (GD_CHAR_ROWS * GD_CHAR_COLS)


; Sets all characters to ' '
; On exit A, X, Y are preserved
gdc_char_buffer_clear:
  pha

  lda #<GDC_CHAR_BUFFER
  sta GDC_CHAR_PTR
  lda #>GDC_CHAR_BUFFER
  sta GDC_CHAR_PTR + 1
.loop:
  lda #' '
  sta (GDC_CHAR_PTR)  
  inc GDC_CHAR_PTR
  bne .ptr_incremented
  inc GDC_CHAR_PTR + 1
.ptr_incremented:
  lda GDC_CHAR_PTR
  cmp #<GDC_CHAR_BUFFER_STOP
  bne .loop
  lda GDC_CHAR_PTR + 1
  cmp #>GDC_CHAR_BUFFER_STOP
  bne .loop

  pla
  rts


; On entry A contains the character to store
;          GD_ROW, GD_COL contain the location to store at
; On exit A, X, Y are preserved
gdc_char_store:
  jsr gdc_char_ptr_from_row_col
  sta (GDC_CHAR_PTR)
  rts


gdc_clear_line:
  phy

  stz GD_COL
  jsr gdc_char_ptr_from_row_col
  lda #' '
  ldy #0
.loop:
  sta (GDC_CHAR_PTR),Y
  iny
  cpy #GD_CHAR_COLS
  bne .loop

  ply
  rts


; On exit A, X, Y are preserved
gdc_char_ptr_from_row_col:
  pha
  phy

  ; set A to GD_ROW adjusted based on GD_SCROLL_ROWS
  clc
  lda GD_ROW
  adc GD_SCROLL_ROWS
  cmp #GD_CHAR_ROWS
  bcc .row_ok
  sec
  sbc #GD_CHAR_ROWS
.row_ok:

  ; multiply A * GD_CHAR_COLS
  ldy #GD_CHAR_COLS
  jsr multiply8x8
  sta GDC_CHAR_PTR + 1

  ; GDC_CHAR_PTR <- GDC_CHAR_BUFFER + GD_ROWS * GD_CHAR_COLS
  clc
  lda #<GDC_CHAR_BUFFER
  adc MULTIPLY_8X8_RESULT_LOW
  sta GDC_CHAR_PTR
  lda #>GDC_CHAR_BUFFER
  adc GDC_CHAR_PTR + 1
  sta GDC_CHAR_PTR + 1
  
  ; GDC_CHAR_PTR <- GDC_CHAR_PTR + GD_COL
  clc
  lda GDC_CHAR_PTR
  adc GD_COL
  sta GDC_CHAR_PTR
  bcc .addition_done
  inc GDC_CHAR_PTR + 1
.addition_done:
  ply
  pla
  rts
