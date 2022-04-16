  .include base_config_wendy2.inc

DISPLAY_STRING_PARAM  = $00 ; 2 bytes

LED_MASK              = %01000000
LED_PORT              = PORTB

  .org $4000
  jmp program_entry

  ; Place code for delay_routines at start of page to ensure no page boundary crossings
  ; during timing loops
  .include delay_routines.inc

  .include display_routines_4bit.inc
  .include display_string.inc


program_entry:
  lda #BANK_MASK
  trb BANK_PORT
  tsb BANK_PORT + DDR_OFFSET
  lda #%00000100
  tsb BANK_PORT

  jsr clear_display

  lda #<message
  ldx #>message
  jsr display_string


  lda #LED_MASK
  trb LED_PORT
  tsb LED_PORT + DDR_OFFSET


forever:
  lda #125
  jsr delay_10_thousandths
  lda #125
  jsr delay_10_thousandths

  jsr test_delays
  bra forever


test_delays:

  jsr toggle_output

  lda #150
  jsr delay_10_thousandths

  jsr toggle_output

  lda #41
  jsr delay_10_thousandths

  jsr toggle_output

  lda #1
  jsr delay_10_thousandths

  jsr toggle_output

  rts


toggle_output:
  lda LED_PORT
  EOR #LED_MASK
  sta LED_PORT

  rts


message: asciiz "Test delay routines"
