DISPLAY_STRING_PARAM  = $0000

COUNTER               = $0002

BUFFER_WRITE_POS      = $0003
BUFFER_READ_POS       = $0004
CHAR_BUFFER           = $0200


  .org $fc00
reset:
  ldx #$ff ; Initialize stack
  txs

  lda #$12
  sta COUNTER

loop:
  lda #<message
  ldx #>message
  jsr display_string
 
  lda COUNTER
  jsr display_hex

  lda #13
  jsr display_character
  lda #10
  jsr display_character

  inc COUNTER
  bra loop

  wai


message:
  .asciiz "Value: 0x"


; On entry A = byte to display in hex
; On exit  A, X, Y are preserved
display_hex:
  pha
  phx
  jsr convert_to_hex
  jsr display_character
  txa
  jsr display_character
  plx
  pla
  rts


; On entry A = value to convert
; On exit  X = low result
;          A = high result
;          Y is preserved
convert_to_hex:
  pha
  and #$0f
  cmp #10
  bcs convert_to_hex_character_low
  adc #'0'
  bra convert_to_hex_done_low
convert_to_hex_character_low:
  clc
  adc #('A' - 10)
convert_to_hex_done_low:
  tax
  pla
  lsr
  lsr
  lsr
  lsr
  cmp #10
  bcs convert_to_hex_character_high
  adc #'0'
  rts
convert_to_hex_character_high:
  clc
  adc #('A' - 10)
  rts


display_string:
  phy
  sta DISPLAY_STRING_PARAM
  stx DISPLAY_STRING_PARAM + 1
  ldy #0
print_loop:
  lda (DISPLAY_STRING_PARAM),Y
  beq done_printing
  jsr display_character
  iny
  bra print_loop
done_printing:
  ply
  rts


display_character:
  pha
  phx
  jsr wait_not_full
  ldx BUFFER_WRITE_POS
  sta CHAR_BUFFER,X
  inx
  stx BUFFER_WRITE_POS
  plx
  pla
  rts


wait_not_full:
  pha
wait_not_full_loop:
  lda BUFFER_WRITE_POS
  cmp BUFFER_READ_POS
  bmi wait_not_full_loop
  pla
  rts


  .org $fffc
  .word reset
  .word $0000
