CLOCK_FREQ_KHZ      = 2000

BASE_ADDRESS_6522   = $F000

DISPLAY_BITS        = 4

DISPLAY_DATA_PORT   = PORTA
DISPLAY_DATA_MASK   = %11110000
RW                  = %00001000
RS                  = %00000100
BF                  = %10000000
DISPLAY_BITS_MASK   = (DISPLAY_DATA_MASK | RW | RS)

DISPLAY_ENABLE_PORT = PORTB
E                   = %00100000

  .org $8000

  .include 6522.inc
  .include delay_routines.inc

  .include display_routines.inc


; Set port directions
initialize_ports_for_display:
  lda #DISPLAY_BITS_MASK
  trb DISPLAY_DATA_PORT
  tsb DISPLAY_DATA_PORT + DDR_OFFSET

  lda #E
  trb DISPLAY_ENABLE_PORT
  tsb DISPLAY_ENABLE_PORT + DDR_OFFSET

  rts


DISPLAY_STRING_PARAM = $00 ; 2 bytes

  .include display_string.inc


message: .asciiz "Hi! I'm Wendy 2"


reset:
  ldx #$ff                                 ; Initialize stack
  txs

  lda #0                                   ; Initialize status flags
  pha
  plp

  jsr initialize_ports_for_display         ; Prepare the display
  jsr reset_and_enable_display_no_cursor


  lda #%01000000                           ; Prepare to flash LED
  tsb DDRB

loop:
  lda #%01000000
  tsb PORTB

  lda #<message                            ; Display a message
  ldx #>message
  jsr display_string

  jsr delay

  lda #%01000000
  trb PORTB                                ; Light is on when low

  jsr clear_display

  jsr delay

  bra loop

delay:
  ldx #0
loop2:

  ldy #0
loop3:
  nop
  nop
  nop
  nop
  dey
  bne loop3

  dex
  bne loop2

  rts

  .org $fffc
  .word reset
  .word $0000
