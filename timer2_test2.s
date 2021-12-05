  .include base_config_v1.inc

JIFFY_HZ = 500

DELAY = CLOCK_FREQ_KHZ / JIFFY_HZ * 1000

DISPLAY_STRING_PARAM    = $00 ; 2 bytes
TO_DECIMAL_PARAM        = $02 ; 9 bytes
COUNTER                 = $0b ; 4 bytes
COUNTER_COPY            = $0f ; 4 bytes
JIFFY_COUNTER           = $13 ; 1 bytes
HUNDREDTHS_COUNTER      = $14 ; 1 bytes
SECONDS_COUNTER         = $15 ; 1 byte
MINUTES_COUNTER         = $16 ; 1 byte
HOURS_COUNTER           = $17 ; 1 byte
HUNDREDTHS_COUNTER_COPY = $18 ; 1 byte
SECONDS_COUNTER_COPY    = $19 ; 1 byte
MINUTES_COUNTER_COPY    = $1a ; 1 byte
HOURS_COUNTER_COPY      = $1b ; 1 byte

  .org $2000

  lda #<interrupt
  sta RAM_IRQ_VECTOR + 0
  lda #>interrupt
  sta RAM_IRQ_VECTOR + 1

  stz COUNTER + 0
  stz COUNTER + 1
  stz COUNTER + 2
  stz COUNTER + 3

  stz JIFFY_COUNTER
  lda #0
  sta HOURS_COUNTER
  lda #0
  sta MINUTES_COUNTER
  lda #0
  sta SECONDS_COUNTER
  lda #0
  sta HUNDREDTHS_COUNTER

  lda #<start_message
  ldx #>start_message
  jsr display_string

  lda #ACR_T2_TIMED ; Timer 2 one shot run mode
  sta ACR

  lda #<DELAY
  sta T2CL
  lda #>DELAY
  sta T2CH

  lda #(IERSETCLEAR | IT2) ; Enable timer 1 and 2 interrupts
  sta IER

  cli

loop:
  ; Copy data that is set by interrupt routines and reset timer done
  sei
  lda COUNTER      + 0
  sta COUNTER_COPY + 0
  lda COUNTER      + 1
  sta COUNTER_COPY + 1
  lda COUNTER      + 2
  sta COUNTER_COPY + 2
  lda COUNTER      + 3
  sta COUNTER_COPY + 3
  lda HUNDREDTHS_COUNTER
  sta HUNDREDTHS_COUNTER_COPY
  lda SECONDS_COUNTER
  sta SECONDS_COUNTER_COPY
  lda MINUTES_COUNTER
  sta MINUTES_COUNTER_COPY
  lda HOURS_COUNTER
  sta HOURS_COUNTER_COPY
  cli

  lda #DISPLAY_FIRST_LINE + 7
  jsr move_cursor

  lda COUNTER_COPY + 3
  jsr display_hex
  lda COUNTER_COPY + 2
  jsr display_hex
  lda COUNTER_COPY + 1
  jsr display_hex
  lda COUNTER_COPY + 0
  jsr display_hex

  lda #DISPLAY_SECOND_LINE

  jsr move_cursor
  lda HOURS_COUNTER_COPY
  jsr display_time_component
  lda #':'
  jsr display_character
  lda MINUTES_COUNTER_COPY
  jsr display_time_component
  lda #':'
  jsr display_character
  lda SECONDS_COUNTER_COPY
  jsr display_time_component
  lda #'.'
  jsr display_character
  lda HUNDREDTHS_COUNTER_COPY
  jsr display_time_component

  ldx #0
delay1:
  ldy #0
delay2:
  dey
  bne delay2
  dex
  bne delay1

  jmp loop


start_message: asciiz "Start."
done_message:  asciiz " Done: "


interrupt:
  pha
  phx
  phy

RESTART_OFFSET = 1
RESTART_CYCLES = 33 + RESTART_OFFSET

  ; Read from timer low counter which also clears the interrupt
  ldx T2CL               ; *4 cycles - value read (when?)
  ldy T2CH               ; *4 cycles

  ; Adjust timer high if timer low is in range 0..3
  txa                    ; *2 cycles
  and #%11111100         ; *2 cycles
                         ;   Adjust         No Adjust
  bne timer_no_adjust    ;   2 cycles       3 cycles
  iny                    ;   2 cycles       -
  bra timer_ok           ;   3 cycles       -
timer_no_adjust:         ;
  nop                    ;   -              2 cycles
  nop                    ;   -              2 cycles
                         ; *7 cycles total
timer_ok:

ADJUSTED_DELAY = DELAY - RESTART_CYCLES

  clc                    ; *2 cycles
  txa                    ; *2 cycles
  adc #<ADJUSTED_DELAY   ; *2 cycles
  sta T2CL               ; *4 cycles
  tya                    ; *2 cycles
  adc #>ADJUSTED_DELAY   ; *2 cycles
  sta T2CH               ; *4 cycles - restart timer (when?)

  inc COUNTER + 0
  bne inc_counter_done
  inc COUNTER + 1
  bne inc_counter_done
  inc COUNTER + 2
  bne inc_counter_done
  inc COUNTER + 3
inc_counter_done:

  ; increment jiffies
  inc JIFFY_COUNTER
  lda JIFFY_COUNTER
  cmp #<(JIFFY_HZ / 100)
  bne increment_done
  stz JIFFY_COUNTER
  ; increment hundredths
  inc HUNDREDTHS_COUNTER
  lda HUNDREDTHS_COUNTER
  cmp #100
  bne increment_done
  stz HUNDREDTHS_COUNTER
  ; increment seconds
  inc SECONDS_COUNTER
  lda SECONDS_COUNTER
  cmp #60
  bne increment_done
  stz SECONDS_COUNTER
  ; increment minutes
  inc MINUTES_COUNTER
  lda MINUTES_COUNTER
  cmp #60
  bne increment_done
  stz MINUTES_COUNTER
  ; increment hours
  inc HOURS_COUNTER
  lda HOURS_COUNTER
  cmp #24
  bne increment_done
  stz HOURS_COUNTER

increment_done:

  ply
  plx
  pla
  rti


; On entry A contains the value to display as 2 digit decimal
; On exit X, Y are preserved
;         A is not preserved
display_time_component:
  phx
  tax
  cmp #10
  bcs dtc_no_leading_zero
  lda #'0'
  jsr display_character
dtc_no_leading_zero:
  txa
  ldx #0
  jsr display_decimal
  plx
  rts


  .include display_update_routines_4bit.inc
  .include display_hex.inc
  .include display_string.inc
  .include display_decimal.inc
