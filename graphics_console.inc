; Requires:
;   GC_ZERO_PAGE_BASE         - location in zero page for variables
;   GC_LINE_BUFFER            - GD_CHAR_ROWS * GD_CHAR_COLS bytes for storing entered line (including terminating 0)
;
;   References functions from graphics_display.inc and keyboard_driver.inc (user should include these)
;
; Optional:
;   GC_TAB_WIDTH              - tab width (default 4)
;   GD_PROMPT_CHAR            - prompt character (default '>')
;   gc_callback_gc_char_received - callback function called with A = character recieved (should preserve all registers)

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
  jsr gc_write_char_to_screen
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
  jsr gc_char_received
  bcs .done
  jsr keyboard_get_char
  bcc .get_char_loop_2
  bra .get_char_loop
.done
  ply
  plx
  pla
  rts


; Show the prompt on the graphics console
; On exit A, X, Y are preserved
gc_show_prompt:
  pha
  jsr gd_select
  lda GD_COL
  beq .at_start_of_line
  lda GD_ROW
  cmp #GD_CHAR_ROWS - 1
  bne .not_last_line
  jsr gc_do_scroll
  bra .prompt
.not_last_line
  jsr gd_next_line
.prompt
  stz GD_COL
.at_start_of_line:
  lda #GC_PROMPT_CHAR
  jsr gd_show_character
  jsr gd_next_character
  jsr gd_unselect
  pla
  rts


; Internal function - handle a character received
gc_char_received:
  .ifdef gc_callback_gc_char_received
  jsr gc_callback_gc_char_received
  .endif

  jsr gd_select
  jsr gc_handle_char_from_keyboard
  php ; preserve carry flag
  jsr gd_unselect
  plp
  rts


; Handle a character from the keyboard. Can be called to simulate key presses
; On exit TODO which registers are preserved
gc_handle_char_from_keyboard:
  phx
  cmp #ASCII_BACKSPACE
  beq .backspace
  cmp #ASCII_LF
  beq .newline
; normal_char:
  tax
  lda GC_START_ROW
  bne .store_char
  lda GD_ROW
  cmp #GD_CHAR_ROWS - 1
  bne .store_char
  lda GD_COL
  cmp #GD_CHAR_COLS - 1
  beq .return ; Have filled up the entire screen
.store_char:
  txa
  jsr gc_line_buffer_add
  cmp #ASCII_TAB
  bne .show_char
; tab:
  lda #' '
.show_char:
  jsr gd_show_character
  lda GD_COL
  cmp #GD_CHAR_COLS - 1
  bne .not_last_char
  lda GD_ROW
  cmp #GD_CHAR_ROWS - 1
  bne .not_last_char
  jsr gc_do_scroll
  bra .done
.not_last_char:
  jsr gd_next_character
  bra .done
.backspace:
  lda GD_ROW
  cmp GC_START_ROW
  bne .not_first_char
  lda GD_COL
  cmp GC_START_COL
  beq .return
.not_first_char:
  jsr gc_line_buffer_delete
  lda #' '
  jsr gd_show_character
  lda GD_COL
  beq .previous_line
  dec
  sta GD_COL
  bra .done
.previous_line:
  dec GD_ROW
  lda #GD_CHAR_COLS - 1
  sta GD_COL
  bra .done
.newline:
  lda #' '
  jsr gd_show_character
  lda GD_ROW
  cmp #GD_CHAR_ROWS - 1
  bne .not_last_line
  jsr gc_do_scroll
  bra .line_read
.not_last_line:  
  jsr gd_next_line
.line_read:
  lda #ASCII_LF
  jsr gc_line_buffer_add
  lda #0
  jsr gc_line_buffer_add
  sec
  bra .return2
.done:
  lda #'_'
  jsr gd_show_character
.return
  clc
.return2
  plx
  rts


; On entry A contains the character to write
; On exit X, Y are preserved
;         A is not preserved
gc_write_char_to_screen:
  cmp #ASCII_TAB
  beq .tab
  cmp #ASCII_LF
  beq .newline
  jsr gd_show_character
  lda GD_COL
  cmp #GD_CHAR_COLS - 1
  bne .not_last_char
  lda GD_ROW
  cmp #GD_CHAR_ROWS - 1
  bne .not_last_char
  jsr gc_do_scroll
  bra .done
.not_last_char:
  jsr gd_next_character
  bra .done
.tab:
  jsr gc_do_tab
  bra .done
.newline:
  lda GD_ROW
  cmp #GD_CHAR_ROWS - 1
  bne .not_last_line
  jsr gc_do_scroll
  bra .done
.not_last_line:  
  jsr gd_next_line
.done:
  rts


; On exit X, Y are preserved
;         A is not preserved
gc_do_tab:
  lda #' '
  jsr gd_show_character
  lda #GC_TAB_WIDTH
.loop:
  cmp #GD_CHAR_COLS
  bcs .next_line
  cmp GD_COL
  beq .over1
  bcs .move_cursor ; A > GD_COL
.over1
  clc
  adc #GC_TAB_WIDTH
  bra .loop
.next_line
  lda GD_ROW
  cmp #GD_CHAR_ROWS - 1
  bne .not_last_line
  jmp gc_do_scroll ; tail call
.not_last_line:
  jmp gd_next_line ; tail call
.move_cursor:
  sta GD_COL
  rts

; Scroll up by 1 line
; On exit X, Y are preserved
;         A is not preserved
gc_do_scroll:
  phx
  phy

  stz GD_ROW
  jsr gd_clear_line
  lda #1
  jsr gd_scroll_up
  lda #GD_CHAR_ROWS - 1
  sta GD_ROW
  stz GD_COL

  dec GC_START_ROW

  ply
  plx
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


gc_show_line_buffer:
  lda #<GC_LINE_BUFFER
  ldx #>GC_LINE_BUFFER
  jsr write_string_to_screen
  rts
