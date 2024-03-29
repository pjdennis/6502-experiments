CLOCK_FREQ_KHZ    = 5000

; PORTA assignments
BANK_MASK         = %00001111
SD_CSB            = %10000000

BANK_START        = %00000100
BANK_STOP         = %00010000

; PORTB assignments
DISPLAY_DATA_PORT   = PORTB
DISPLAY_DATA_MASK   = %01111000
RW                  = %00000010
RS                  = %00000001
BF                  = %01000000
DISPLAY_BITS_MASK   = (DISPLAY_DATA_MASK | RW | RS)

DISPLAY_ENABLE_PORT = PORTB
E                   = %00000100

DISPLAY_BITS = 4

;16x2 LCD
DISPLAY_WIDTH     = 16
DISPLAY_HEIGHT    = 2
DISPLAY_LAST_LINE = DISPLAY_SECOND_LINE

;20x4 LCD
;DISPLAY_WIDTH     = 20
;DISPLAY_HEIGHT    = 4
;DISPLAY_LAST_LINE = DISPLAY_FOURTH_LINE

RAM_IRQ_VECTOR    = $3ffe

; Include additional definitions
  .include display_parameters.inc
  .include 6522.inc

