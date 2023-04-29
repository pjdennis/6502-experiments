; Requires:
;   display_routines.inc
;   display_string.inc

sk_init:
  jsr clear_display
  lda #<.start_message
  ldx #>.start_message
  jsr display_string
  rts
.start_message: .asciiz "Last key press:"


; On entry A = character recieved
; On exit A, X, Y are preserved
sk_show_char_info:
  phx
  tax
  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  txa
  jsr display_character
  lda #' '
  jsr display_character
  txa
  jsr display_hex
  txa
  plx
  rts

