DELAY = $e000

DISPLAY_STRING_PARAM    = $00 ; 2 bytes
TIMER_DONE              = $02 ; 1 byte

TIMER_LOW               = $03 ; 1 byte
TIMER_HIGH              = $04 ; 1 byte
TIMER_OVERRUN_LOW       = $05 ; 1 byte
TIMER_OVERRUN_HIGH      = $06 ; 1 byte
NEW_DELAY_LOW           = $07 ; 1 byte
NEW_DELAY_HIGH          = $08 ; 1 byte
INT_COUNT_LOW           = $09 ; 1 byte
INT_COUNT_HIGH          = $0a ; 1 byte

TIMER_LOW_COPY          = $0b ; 1 byte
TIMER_HIGH_COPY         = $0c ; 1 byte
TIMER_OVERRUN_LOW_COPY  = $0d ; 1 byte
TIMER_OVERRUN_HIGH_COPY = $0e ; 1 byte
NEW_DELAY_LOW_COPY      = $0f ; 1 byte
NEW_DELAY_HIGH_COPY     = $10 ; 1 byte
INT_COUNT_LOW_COPY      = $11 ; 1 byte
INT_COUNT_HIGH_COPY     = $12 ; 1 byte


  .include base_config_v1.inc

  .org $2000

  lda #<interrupt
  sta RAM_IRQ_VECTOR + 0
  lda #>interrupt
  sta RAM_IRQ_VECTOR + 1 

  lda #<start_message
  ldx #>start_message
  jsr display_string

  stz INT_COUNT_LOW
  stz INT_COUNT_HIGH
  stz TIMER_DONE

  lda #0 ; Timer 2 one shot run mode
  sta ACR

  lda #<DELAY
  sta T2CL
  lda #>DELAY
  sta T2CH

  lda #(IERSETCLEAR | IT2) ; Enable timer 2 interrupts
  sta IER

  cli

loop:
wait:
  sei
  nop
  nop
  lda TIMER_DONE
  cli
  beq wait

  ; Copy data that is set by interrupt routines and reset timer done
  sei
  stz TIMER_DONE

  lda TIMER_HIGH
  sta TIMER_HIGH_COPY
  lda TIMER_LOW
  sta TIMER_LOW_COPY

  lda TIMER_OVERRUN_HIGH
  sta TIMER_OVERRUN_HIGH_COPY
  lda TIMER_OVERRUN_LOW
  sta TIMER_OVERRUN_LOW_COPY

  lda NEW_DELAY_HIGH
  sta NEW_DELAY_HIGH_COPY
  lda NEW_DELAY_LOW
  sta NEW_DELAY_LOW_COPY

  lda INT_COUNT_LOW
  sta INT_COUNT_LOW_COPY
  lda INT_COUNT_HIGH
  sta INT_COUNT_HIGH_COPY
  cli

  lda #DISPLAY_FIRST_LINE + 8
  jsr move_cursor

  lda INT_COUNT_HIGH_COPY
  jsr display_hex
  lda INT_COUNT_LOW_COPY
  jsr display_hex

  lda #DISPLAY_SECOND_LINE + 0
  jsr move_cursor

  lda TIMER_HIGH_COPY
  jsr display_hex
  lda TIMER_LOW_COPY
  jsr display_hex

  jsr display_space

  lda TIMER_OVERRUN_HIGH_COPY
  jsr display_hex
  lda TIMER_OVERRUN_LOW_COPY
  jsr display_hex

  jsr display_space

  lda NEW_DELAY_HIGH_COPY
  jsr display_hex
  lda NEW_DELAY_LOW_COPY
  jsr display_hex

  ldx #0
delay1:
  ldy #0
delay2:
  nop
  nop
  dey
  bne delay2
  dex
  bne delay1

  bra loop


start_message: asciiz "Start.."
done_message:  asciiz " Done: "


interrupt:
  pha
  phx
  phy


READ_OFFSET = -3
START_OFFSET = 1
RESTART_CYCLES = 33 + READ_OFFSET + START_OFFSET

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
  adc #>ADJUSTED_DELAY  ; *2 cycles
  sta T2CH               ; *4 cycles - restart timer (when?)

  ; Store timer as read
  stx TIMER_LOW
  sty TIMER_HIGH

  ; store new delay (repetition of the calculation above)
  clc
  txa
  adc #<ADJUSTED_DELAY
  sta NEW_DELAY_LOW
  tya
  adc  #>ADJUSTED_DELAY
  sta NEW_DELAY_HIGH

  sec
  lda #0
  sbc TIMER_LOW
  sta TIMER_OVERRUN_LOW
  lda #0
  sbc TIMER_HIGH
  sta TIMER_OVERRUN_HIGH

  inc INT_COUNT_LOW
  bne inc_done
  inc INT_COUNT_HIGH
inc_done:

  inc TIMER_DONE

  ply
  plx
  pla
  rti

  .include display_update_routines_4bit.inc
  .include display_hex.inc
  .include display_string.inc
