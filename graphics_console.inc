; Requires:
;   GC_ZERO_PAGE_BASE         - location in zero page for variables
;   GC_LINE_BUFFER            - GD_CHAR_ROWS * GD_CHAR_COLS bytes for storing entered line (including terminating 0)
;
;   References functions from graphics_display.inc and keyboard_driver.inc (user should include these)
;
; Optional:
;   GC_TAB_WIDTH              - tab width (default 4)
;   GD_PROMPT_CHAR            - prompt character (default '>')
;   gc_callback_char_received - callback function called with A = character recieved (should preserve all registers)

  .ifndef GC_TAB_WIDTH
GC_TAB_WIDTH      = 4
  .endif

  .ifndef GC_PROMPT_CHAR
GC_PROMPT_CHAR    = '>'
  .endif

GC_START_ROW      = GC_ZERO_PAGE_BASE + $00 ; 1 byte
GC_START_COL      = GC_ZERO_PAGE_BASE + $01 ; 1 byte
GC_LINE_PTR       = GC_ZERO_PAGE_BASE + $02 ; 2 bytes

GC_ZERO_PAGE_STOP = GC_ZERO_PAGE_BASE + $04


; On exit A, X, Y are preserved
gc_initialize:
  jsr gc_initialize_line_ptr
  stz GC_LINE_BUFFER
  rts


gc_initialize_line_ptr:
  lda #<GC_LINE_BUFFER
  sta GC_LINE_PTR
  lda #>GC_LINE_BUFFER
  sta GC_LINE_PTR + 1
  rts


gc_line_buffer_add:
  sta (GC_LINE_PTR)
  inc GC_LINE_PTR
  bne .done
  inc GC_LINE_PTR + 1
.done:
  rts


gc_line_buffer_delete:
  pha
  lda GC_LINE_PTR
  bne .high_byte_good
  dec GC_LINE_PTR + 1
.high_byte_good:
  dec GC_LINE_PTR
  pla
  rts

