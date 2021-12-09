; Requires CREATE_CHARACTER_PARAM (2 bytes in zero page)

ASCII_TAB                = 0x09
ASCII_TILDE              = 0x7e
ASCII_BACKSLASH          = 0x5c

CHARACTER_RIGHT_ARROW    = 0x7e


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
  cmp #ASCII_TILDE
  beq .tilde
  cmp #ASCII_BACKSLASH
  beq .backslash
  cmp #ASCII_TAB
  beq .tab
  rts
.tilde:
  lda #CHARACTER_TILDE
  rts
.backslash:
  lda #CHARACTER_BACKSLASH
  rts
.tab
  lda #CHARACTER_RIGHT_ARROW
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

