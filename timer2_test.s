DELAY = $e000

DISPLAY_STRING_PARAM = $00 ; 2 bytes
TIMER_DONE           = $02 ; 1 byte
TIMER_LOW            = $03 ; 1 byte
TIMER_HIGH_RAW       = $04 ; 1 byte
TIMER_HIGH_ADJUSTED  = $05 ; 1 byte
TIMER_OVERRUN_LOW    = $06 ; 1 byte
TIMER_OVERRUN_HIGH   = $07 ; 1 byte
NEW_DELAY_LOW        = $08 ; 1 byte
NEW_DELAY_HIGH       = $09 ; 1 byte


  .include base_config_v1.inc

  .org $2000

  lda #<interrupt
  sta RAM_IRQ_VECTOR + 0
  lda #>interrupt
  sta RAM_IRQ_VECTOR + 1 

  lda #<start_message
  ldx #>start_message
  jsr display_string

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

wait:
  lda TIMER_DONE
  beq wait

  lda #<done_message
  ldx #>done_message
  jsr display_string

  lda TIMER_HIGH_RAW
  jsr display_hex

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor

  lda TIMER_HIGH_ADJUSTED
  jsr display_hex
  lda TIMER_LOW
  jsr display_hex

  jsr display_space

  lda TIMER_OVERRUN_HIGH
  jsr display_hex
  lda TIMER_OVERRUN_LOW
  jsr display_hex

  jsr display_space

  lda NEW_DELAY_HIGH
  jsr display_hex
  lda NEW_DELAY_LOW
  jsr display_hex

  stp


start_message: asciiz "Start.."
done_message:  asciiz " Done: "


interrupt:
  pha
  phx
  phy

  ; When iterations = 1; TIMER_LOW reads as E4 (228 decimal)
  ; 5 Cycles per iteration means 228 / 5 = 45
  ; 228 - 45 * 5 = 3 so we would expect to read as FE 03 (confirmed)
  ; 228 - 44 * 5 = 8 so we would expect to read as FF 08 (confirmed)
  ; 44 with 2 extra noops that adds four cycles so FF 04 (confirmed)
  ; 45 with 2 extra noops that adds four cycles so FE FF (confirmed)

  nop
  nop

  ldy #(1 + 45)
delay:       ; 5 cycles per iteration
  dey        ; 2 cycles
  bne delay  ; 3 cycles when taken

  lda T2CL ; Read from timer low counter which also clears the interrupt
  ldx T2CH
  sta TIMER_LOW
  stx TIMER_HIGH_RAW

  ; Check if timer low is in range 0..3
  and #%11111100         ; Adjust         No Adjust
  bne timer_no_adjust    ; 2 cycles       3 cycles
  inx                    ; 2 cycles       -
  bra timer_ok           ; 3 cycles       -
timer_no_adjust:         ;
  nop                    ; -              2 cycles
  nop                    ; -              2 cycles
                         ; 7 total        7 total
timer_ok:
  stx TIMER_HIGH_ADJUSTED

  sec
  lda #0
  sbc TIMER_LOW
  sta TIMER_OVERRUN_LOW
  lda #0
  sbc TIMER_HIGH_ADJUSTED
  sta TIMER_OVERRUN_HIGH

RESTART_CYCLES = 1
ADJUSTED_DELAY = DELAY - RESTART_CYCLES

  clc
  lda #<ADJUSTED_DELAY
  adc TIMER_LOW
  sta NEW_DELAY_LOW
  lda #>ADJUSTED_DELAY
  adc TIMER_HIGH_ADJUSTED
  sta NEW_DELAY_HIGH

  inc TIMER_DONE

  ply
  plx
  pla
  rti

  .include display_update_routines_4bit.inc
  .include display_hex.inc
  .include display_string.inc
