DELAY = 100

DISPLAY_STRING_PARAM    = $00 ; 2 bytes

  .include base_config_v1.inc

  .org $2000

  lda #<interrupt
  sta RAM_IRQ_VECTOR + 0
  lda #>interrupt
  sta RAM_IRQ_VECTOR + 1

  lda #ACR_T2_TIMED ; Timer 2 one shot run mode
  sta ACR

  lda #<DELAY
  sta T2CL
  lda #>DELAY
  sta T2CH

  lda #(IERSETCLEAR | IT2) ; Enable timer 2 interrupts
  sta IER

  cli

  lda #<start_message
  ldx #>start_message
  jsr display_string

loop:
  bra loop

start_message: asciiz "Timer running."


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

;  inc T2_INT_COUNT_LOW
;  bne inc_t2_count_done
;  inc T2_INT_COUNT_HIGH
;inc_t2_count_done:

  ply
  plx
  pla
  rti

  .include display_update_routines_4bit.inc
  .include display_hex.inc
  .include display_string.inc
