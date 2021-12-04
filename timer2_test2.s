  .include base_config_v1.inc

DELAY = CLOCK_FREQ_KHZ / 10 ; 100 microseconds

DISPLAY_STRING_PARAM    = $00 ; 2 bytes
COUNTER                 = $02 ; 4 bytes
COUNTER_COPY            = $06 ; 4 bytes

  .org $2000

  lda #<interrupt
  sta RAM_IRQ_VECTOR + 0
  lda #>interrupt
  sta RAM_IRQ_VECTOR + 1

  stz COUNTER + 0
  stz COUNTER + 1
  stz COUNTER + 2
  stz COUNTER + 3

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
  lda COUNTER
  sta COUNTER_COPY
  lda COUNTER + 1
  ldx COUNTER + 2
  ldy COUNTER + 3
  cli
  sta COUNTER_COPY + 1
  stx COUNTER_COPY + 2
  sty COUNTER_COPY + 3

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

  inc COUNTER
  bne inc_counter_done
  inc COUNTER + 1
  bne inc_counter_done
  inc COUNTER + 2
  bne inc_counter_done
  inc COUNTER + 3
inc_counter_done:

  ply
  plx
  pla
  rti

  .include display_update_routines_4bit.inc
  .include display_hex.inc
  .include display_string.inc
