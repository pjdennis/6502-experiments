CLOCK_FREQ_KHZ    = 1000

; PORTA assignments
E    = %10000000  ; Display enable
RW   = %01000000  ; Display read/write
RS   = %00100000  ; Display register select

SOEB = %00010000  ; Shift register output enable (active low) 

; Include additional definitions
  .include display_parameters.inc
  .include 6522.inc

