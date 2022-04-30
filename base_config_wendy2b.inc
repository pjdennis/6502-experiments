CLOCK_FREQ_KHZ      = 13500

BASE_ADDRESS_6522   = $F000

; Memory Banking
BANK_PORT           = PORTB
BANK_MASK           = %00001111

BANK_START          = %00000001
BANK_STOP           = %00010000

; Display
DISPLAY_DATA_PORT   = PORTA
DISPLAY_DATA_MASK   = %11110000
RW                  = %00001000
RS                  = %00000100
BF                  = %10000000
DISPLAY_BITS_MASK   = (DISPLAY_DATA_MASK | RW | RS)

DISPLAY_ENABLE_PORT = PORTB
E                   = %00100000

DISPLAY_BITS = 4

;16x2 LCD
DISPLAY_WIDTH     = 16
DISPLAY_HEIGHT    = 2
DISPLAY_LAST_LINE = DISPLAY_SECOND_LINE

;20x4 LCD
;DISPLAY_WIDTH     = 20
;DISPLAY_HEIGHT    = 4
;DISPLAY_LAST_LINE = DISPLAY_FOURTH_LINE

; Include additional definitions
  .include display_parameters.inc
  .include 6522.inc

