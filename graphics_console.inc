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


; Initialize the graphics console
;
; On exit A, X, Y are preserved
gc_initialize:
  jsr gc_initialize_line_ptr
  stz GC_LINE_BUFFER
  rts


; Print a character from the graphics console
;
; On entry A contains the character to print
; On exit X, Y are preserved
;         A is not preserved
gc_putchar:
  jsr gd_select
  jsr write_character_to_screen
  jsr gd_unselect
  rts


; Get a character from the graphics console
;
; On exit A contains the character read
;         X, Y are preserved
gc_getchar:
  phx
  phy
  lda (GC_LINE_PTR)
  bne .buffer_has_data
; No data so read some
  jsr gc_getline
  jsr gc_initialize_line_ptr
  lda (GC_LINE_PTR)
.buffer_has_data:
  inc GC_LINE_PTR
  bne .done
  inc GC_LINE_PTR + 1
.done
  ply
  plx
  rts


; Get a line from the graphics console
;
; On exit GD_LINE_BUFFER contains the 0-terminated line (which includes the ASCII_LF character)
;         A, X, Y are preserved
gc_getline:
  pha
  phx
  phy

  lda GD_ROW
  sta GC_START_ROW
  lda GD_COL
  sta GC_START_COL
  jsr gc_initialize_line_ptr
  ldx #0
.get_char_loop:
  cpx #0
  bne .not_off
  jsr gd_select
  lda #' '
  jsr gd_show_character
  jsr gd_unselect
.not_off:
  cpx #25
  bne .not_on
  jsr gd_select
  lda #'_'
  jsr gd_show_character
  jsr gd_unselect
.not_on:
  inx
  cpx #50
  bne .no_reset_count
  ldx #0
.no_reset_count:
  lda #1
  jsr delay_hundredths
  jsr keyboard_get_char
  bcs .get_char_loop
.get_char_loop_2:
  jsr char_received
  bcs .done
  jsr keyboard_get_char
  bcc .get_char_loop_2
  bra .get_char_loop
.done
  ply
  plx
  pla
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
