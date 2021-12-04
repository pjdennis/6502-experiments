DELAY = $0100

DISPLAY_STRING_PARAM    = $00 ; 2 bytes

TIMER_LOW               = $03 ; 1 byte
TIMER_HIGH              = $04 ; 1 byte
TIMER_OVERRUN_LOW       = $05 ; 1 byte
TIMER_OVERRUN_HIGH      = $06 ; 1 byte
NEW_DELAY_LOW           = $07 ; 1 byte
NEW_DELAY_HIGH          = $08 ; 1 byte
T2_INT_COUNT_LOW        = $09 ; 1 byte
T2_INT_COUNT_HIGH       = $0a ; 1 byte
T1_INT_COUNT_LOW        = $0b ; 1 byte
T1_INT_COUNT_HIGH       = $0c ; 1 byte

TIMER_LOW_COPY          = $0d ; 1 byte
TIMER_HIGH_COPY         = $0e ; 1 byte
TIMER_OVERRUN_LOW_COPY  = $0f ; 1 byte
TIMER_OVERRUN_HIGH_COPY = $10 ; 1 byte
NEW_DELAY_LOW_COPY      = $11 ; 1 byte
NEW_DELAY_HIGH_COPY     = $12 ; 1 byte
T2_INT_COUNT_LOW_COPY   = $13 ; 1 byte
T2_INT_COUNT_HIGH_COPY  = $14 ; 1 byte
T1_INT_COUNT_LOW_COPY   = $15 ; 1 byte
T1_INT_COUNT_HIGH_COPY  = $16 ; 1 byte

  .include base_config_v1.inc

  .org $2000

  lda #<interrupt
  sta RAM_IRQ_VECTOR + 0
  lda #>interrupt
  sta RAM_IRQ_VECTOR + 1 

  lda #<start_message
  ldx #>start_message
  jsr display_string

  stz T2_INT_COUNT_LOW
  stz T2_INT_COUNT_HIGH
  stz T1_INT_COUNT_LOW
  stz T1_INT_COUNT_HIGH

  lda #(ACR_T1_CONT | ACR_T2_TIMED) ; Timer 1 continuous; timer 2 one shot run mode
  sta ACR

  lda #<(DELAY - 2)
  sta T1CL
  lda #>(DELAY - 2)
  sta T1CH

  lda #<DELAY
  sta T2CL
  lda #>DELAY
  sta T2CH

  lda #(IERSETCLEAR | IT1 | IT2) ; Enable timer 1 and 2 interrupts
  sta IER

  cli

loop:
  ; Copy data that is set by interrupt routines and reset timer done
  sei
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

  lda T2_INT_COUNT_LOW
  sta T2_INT_COUNT_LOW_COPY
  lda T2_INT_COUNT_HIGH
  sta T2_INT_COUNT_HIGH_COPY

  lda T1_INT_COUNT_LOW
  sta T1_INT_COUNT_LOW_COPY
  lda T1_INT_COUNT_HIGH
  sta T1_INT_COUNT_HIGH_COPY
  cli

  lda #DISPLAY_FIRST_LINE + 7
  jsr move_cursor

  lda T2_INT_COUNT_HIGH_COPY
  jsr display_hex
  lda T2_INT_COUNT_LOW_COPY
  jsr display_hex

  jsr display_space

  lda T1_INT_COUNT_HIGH_COPY
  jsr display_hex
  lda T1_INT_COUNT_LOW_COPY
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
  pha
  pla
  pha
  pla
  pha
  pla
  pha
  pla
  pha
  pla
  pha
  pla
  pha
  pla
  pha
  pla
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

  lda #IT2
  bit IFR
  beq not_timer_2

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

  inc T2_INT_COUNT_LOW
  bne inc_t2_count_done
  inc T2_INT_COUNT_HIGH
inc_t2_count_done:

not_timer_2:
  lda #IT1
  bit IFR
  beq not_timer_1

  sta IFR ; Clear T1 interrupt

  inc T1_INT_COUNT_LOW
  bne inc_t1_count_done
  inc T1_INT_COUNT_HIGH
inc_t1_count_done:

not_timer_1:

  ply
  plx
  pla
  rti

  .include display_update_routines_4bit.inc
  .include display_hex.inc
  .include display_string.inc
