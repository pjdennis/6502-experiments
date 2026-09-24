DISPLAY_STRING_PARAM = $00   ; 2 bytes

ORIGIN               = $8000

LED_MASK             = %01000000
LED_PORT             = PORTB


  .include base_config_wendy2.inc

  .org ORIGIN
  jmp program_start

  .include delay_routines.inc
  .include display_string.inc
  .include display_routines_4bit.inc

message_line_1: asciiz "Hello."
message_line_2: asciiz "1Abc 123456xyz"

program_start:
  ldx #$ff ; Initialize stack
  txs

  lda #0   ; Initialize status flags
  pha
  plp


  ; Initialize hardware

  ; Memory Banking
  lda #BANK_MASK
  trb BANK_PORT
  tsb BANK_PORT + DDR_OFFSET

  ; Display
  lda #DISPLAY_BITS_MASK
  trb DISPLAY_DATA_PORT
  tsb DISPLAY_DATA_PORT + DDR_OFFSET

  lda #E
  trb DISPLAY_ENABLE_PORT
  tsb DISPLAY_ENABLE_PORT + DDR_OFFSET

  jsr reset_and_enable_display_no_cursor

  lda #<message_line_1
  ldx #>message_line_1
  jsr display_string

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  lda #<message_line_2
  ldx #>message_line_2
  jsr display_string


  lda #LED_MASK
  trb LED_PORT
  tsb LED_PORT + DDR_OFFSET

.forever:
  lda #50
  jsr delay_hundredths

  lda LED_PORT
  EOR #LED_MASK
  sta LED_PORT
  bra .forever


  .org $fffc
  .word ORIGIN
  .word $0000
