DISPLAY_STRING_PARAM = $00

LED_MASK             = %01000000
LED_PORT             = PORTB

  .include base_config_wendy2c.inc

  .org $4000
  jmp program_entry

  ; Place code for delay_routines at start of page to ensure no page boundary crossings
  ; during timing loops
  .include delay_routines.inc
  .include display_routines_4bit.inc
  .include display_string.inc

program_entry:
  jsr clear_display

  lda #<message
  ldx #>message
  jsr display_string

  lda #LED_MASK
  trb LED_PORT
  tsb LED_PORT + DDR_OFFSET

forever:
  lda #LED_MASK
  tsb LED_PORT

  lda #10
  jsr delay_hundredths

  lda #LED_MASK
  trb LED_PORT

  lda #90
  jsr delay_hundredths

  bra forever  


message: asciiz "LED Flashing..."
