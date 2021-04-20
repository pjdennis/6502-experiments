CLOCK_FREQ_KHZ    = 1000

; PORTA assignments
E    = %10000000  ; Display enable
RW   = %01000000  ; Display read/write
RS   = %00100000  ; Display register select

SOEB   = %00010000  ; Input shift register output enable (active low) 
SOLB   = %00001000  ; Output shift register load / clock low (active low)
START  = %01000000  ; Output start bit - multiplexed with RW
PARITY = %00100000  ; Output parity bit - multiplexed with RS

; Include additional definitions
  .include display_parameters.inc
  .include 6522.inc

