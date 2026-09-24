; Requires:
;   GC_ZERO_PAGE_BASE         - location in zero page for variables
;
;   References functions from graphics_display.inc (user should include these)
;
; Optional:
;   GO_TAB_WIDTH              - tab width (default 4)

  .ifndef GO_TAB_WIDTH
GO_TAB_WIDTH      = 4
  .endif


; Initialize the graphics console
;
; On exit A, X, Y are preserved
gc_initialize:
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
  jmp gd_unselect ; tail call


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
  lda #GO_TAB_WIDTH
.loop:
  cmp #GD_CHAR_COLS
  bcs .next_line
  cmp GD_COL
  beq .over1
  bcs .move_cursor ; A > GD_COL
.over1
  clc
  adc #GO_TAB_WIDTH
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

  ply
  plx
  rts


gc_clear:
  jsr gd_select
  jsr gd_clear_screen
  jsr gd_unselect
  stz GD_ROW
  stz GD_COL
  rts
