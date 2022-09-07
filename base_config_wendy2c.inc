CLOCK_FREQ_KHZ      = 9720

BASE_ADDRESS_6522   = $F000

; Memory Banking
BANK_PORT           = PORTB
BANK_MASK           = %00011111

BANK_START          = %00000001
BANK_STOP           = %00010000

; Display
DISPLAY_DATA_PORT   = PORTA
DISPLAY_DATA_MASK   = %11110000
RW                  = %00001000
RS                  = %00000001
BF                  = %10000000
DISPLAY_BITS_MASK   = (DISPLAY_DATA_MASK | RW | RS)

DISPLAY_ENABLE_PORT = PORTB
E                   = %00100000

; Graphic Display
GD_PORT             = PORTA
GD_CLK              = %00000001
GD_RSTB             = %00000010
GD_CSB              = %00000100
GD_DC               = %00001000
GD_MOSI             = %00010000
GD_MISO             = %00100000

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

