; Requires CREATE_CHARACTER_PARAM (2 bytes in zero page)

ASCII_BACKSPACE          = 0x08
ASCII_TAB                = 0x09
ASCII_NEWLINE            = 0x0a
ASCII_BACKSLASH          = 0x5c
ASCII_TILDE              = 0x7e

CHARACTER_RIGHT_ARROW    = 0x7e
CHARACTER_LEFT_ARROW     = 0x7f
CHARACTER_NEWLINE        = 0xa3

; Use the last two custom character positions
CHARACTER_TILDE          = 6
CHARACTER_BACKSLASH      = 7

character_data_tilde:
  .byte %00000
  .byte %00000
  .byte %00000
  .byte %01101
  .byte %10010
  .byte %00000
  .byte %00000
  .byte %00000

character_data_backslash:
  .byte %00000
  .byte %10000
  .byte %01000
  .byte %00100
  .byte %00010
  .byte %00001
  .byte %00000
  .byte %00000

; On exit A, X, Y are preserved
extend_character_set_init:
  pha
  phx
  phy

  lda #CHARACTER_TILDE
  ldx #<character_data_tilde
  ldy #>character_data_tilde
  jsr extend_character_set_create_character

  lda #CHARACTER_BACKSLASH
  ldx #<character_data_backslash
  ldy #>character_data_backslash
  jsr extend_character_set_create_character

  ply
  plx
  pla
  rts


; On entry A is an ASCII character
; On exit  A is translated to the custom char code if applicable
extend_character_set_translate_for_display:
  cmp #ASCII_BACKSPACE
  bne .check_tab
  lda #CHARACTER_LEFT_ARROW
  rts
.check_tab:
  cmp #ASCII_TAB
  bne .check_newline
  lda #CHARACTER_RIGHT_ARROW
  rts
.check_newline:
  cmp #ASCII_NEWLINE
  bne .check_backslash
  lda #CHARACTER_NEWLINE
  rts
.check_backslash:
  cmp #ASCII_BACKSLASH
  bne .check_tilde
  lda #CHARACTER_BACKSLASH
  rts
.check_tilde:
  cmp #ASCII_TILDE
  bne .done
  lda #CHARACTER_TILDE
.done:
  rts


;On entry A = character number
;         X = low byte source address
;         Y = high byte source address
;On exit  A, X, Y are not preserved
extend_character_set_create_character:
  stx CREATE_CHARACTER_PARAM
  sty CREATE_CHARACTER_PARAM + 1

  asl
  asl
  asl
  ora #CMD_SET_CGRAM_ADDRESS
  jsr display_command

  ldy #0
.repeat:
  lda (CREATE_CHARACTER_PARAM), Y
  jsr display_data

  iny
  cpy #8
  bne .repeat

  rts
