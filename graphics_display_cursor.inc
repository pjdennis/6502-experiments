; Requires
;   GDC_ZERO_PAGE_BASE
;   GDC_CHAR_BUFFER - buffer will store GD_CHAR_ROWS * GD_CHAR_COLS screen characters
;   graphics_display.inc
;   multiply8x8.inc

GDC_CHAR_PTR       = GDC_ZERO_PAGE_BASE + $00 ; 2 bytes
GDC_INVERT         = GDC_ZERO_PAGE_BASE + $02 ; 1 byte

GDC_ZERO_PAGE_STOP = GDC_ZERO_PAGE_BASE + $03

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


gdc_show_cursor:
  pha
  phx
  phy

  ; Set X and Y to top left of cursor
  jsr x_y_from_row_col
  clc
  lda GD_Y
  adc #(16 - 2) ; Character height - cursor height
  sta GD_Y
  bcc .y_ready
  inc GD_Y + 1
.y_ready

  ; Load the character at GD_ROW, GD_COL
  jsr gdc_char_ptr_from_row_col
  lda (GDC_CHAR_PTR)

  ; Set pointer to character data
  jsr set_char_data_ptr

  lda #ILI9341_CASET
  jsr gd_send_command
  lda GD_Y + 1
  jsr gd_send_data
  lda GD_Y
  jsr gd_send_data

  clc
  lda GD_Y
  adc #1
  sta GD_Y
  lda GD_Y + 1
  adc #0
  sta GD_Y + 1

  lda GD_Y + 1
  jsr gd_send_data
  lda GD_Y
  jsr gd_send_data

  lda #ILI9341_PASET
  jsr gd_send_command
  lda GD_X + 1
  jsr gd_send_data
  lda GD_X
  jsr gd_send_data

  clc
  lda GD_X
  adc #11
  sta GD_X
  lda GD_X + 1
  adc #0
  sta GD_X + 1

  lda GD_X + 1
  jsr gd_send_data
  lda GD_X
  jsr gd_send_data

  lda #ILI9341_RAMWR
  jsr gd_send_command

  ldy #1
.col_loop:
  lda (GD_CHAR_DATA_PTR),Y
  eor GDC_INVERT
  rol
  rol
  rol
  sta GD_BYTE
  ldx #2
.row_loop:
  lsr GD_BYTE
  bcc .low_bit
; high bit
  lda #>ILI9341_WHITE
;  jsr gd_send_data
  sta PORTB
  lda #GD_E
  tsb GD_PORT
  trb GD_PORT
;  lda #<ILI9341_WHITE
;;  jsr gd_send_data
;  sta PORTB
;  lda #GD_E
  tsb GD_PORT
  trb GD_PORT
  bra .color_done
.low_bit:
  lda #>ILI9341_BLACK
;  jsr gd_send_data
  sta PORTB
  lda #GD_E
  tsb GD_PORT
  trb GD_PORT
;  lda #<ILI9341_BLACK
;;  jsr gd_send_data
;  sta PORTB
;  lda #GD_E
  tsb GD_PORT
  trb GD_PORT
.color_done:
  dex
  bne .row_loop
  iny
  iny
  cpy #25
  bne .col_loop

  ply
  plx
  pla
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
