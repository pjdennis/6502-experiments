CLOCK_FREQ_KHZ    = 2000

PORTB             = $6000
PORTA             = $6001
DDRB              = $6002
DDRA              = $6003

; PORTA assignments
BANK_MASK         = %00001111

BANK_START        = %00000100
BANK_STOP         = %00010000

; PORTB assignments
DISPLAY_DATA_MASK = %01111000
E                 = %00000100
RW                = %00000010
RS                = %00000001

BF                = %01000000
DISPLAY_BITS_MASK = (DISPLAY_DATA_MASK | E | RW | RS)

; Include additional definitions
  .include display_parameters.inc
  .include 6522.inc

