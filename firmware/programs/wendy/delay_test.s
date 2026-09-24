CLOCK_FREQ_KHZ = 2000

PORTB = $6000
DDRB  = $6002

DISPLAY_DATA_MASK = %01111000
E                 = %00000100
RW                = %00000010
RS                = %00000001

BF                = %01000000
DISPLAY_BITS_MASK = (DISPLAY_DATA_MASK | E | RW | RS)

COUNTER = $00

  .org $2000
  jmp program_entry

  .include delay_routines.inc
  .include display_routines.inc
  .include convert_to_hex.inc

program_entry:
  jsr clear_display

  stz COUNTER
  stz COUNTER + 1
repeat:
  lda #DISPLAY_FIRST_LINE
  jsr move_cursor

  lda COUNTER + 1
  jsr display_hex
  lda COUNTER
  jsr display_hex

  lda #100
  ldx #100
delay_loop:
  jsr delay_10_thousandths
  dex
  bne delay_loop

  inc COUNTER
  bne repeat
  inc COUNTER + 1
  bra repeat
