  .include base_config_wendy2c.inc

IRQ_VECTOR_ADDRESS    = $fffe

TIMER_INTERVAL        = 1000 - 1


DISPLAY_STRING_PARAM  = $00 ; 2 bytes
COUNTER               = $02 ; 2 bytes
COUNTER_COPY          = $04 ; 2 bytes

  .org $4000
  jmp initialize_machine

  ; Place code for delay_routines at start of page to ensure no page boundary crossings
  ; during timing loops
  .include delay_routines.inc

  .include initialize_machine_wendy2c.inc
  .include display_routines_4bit.inc
  .include display_string.inc
  .include display_hex.inc


program_start:
  jsr clear_display

  jsr show_irq_address

  lda #BANK_MASK
  trb BANK_PORT
  lda #BANK_START
  tsb BANK_PORT

  jsr show_irq_address

  lda #<interrupt
  sta IRQ_VECTOR_ADDRESS
  lda #>interrupt
  sta IRQ_VECTOR_ADDRESS + 1

  jsr show_irq_address

  stz COUNTER
  stz COUNTER + 1

  ; Start timer 1 interrupts  
  lda #ACR_T1_CONT
  sta ACR
  lda #<TIMER_INTERVAL
  sta T1CL
  lda #>TIMER_INTERVAL
  sta T1CH
  lda #(IERSETCLEAR | IT1)
  sta IER
  cli

forever:
  sei
  lda COUNTER
  ldx COUNTER + 1
  cli
  sta COUNTER_COPY
  stx COUNTER_COPY + 1

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor

  lda COUNTER_COPY + 1
  jsr display_hex
  lda COUNTER_COPY
  jsr display_hex

  lda #200
  jsr delay_10_thousandths

  bra forever 


show_irq_address:
  lda IRQ_VECTOR_ADDRESS + 1
  jsr display_hex
  lda IRQ_VECTOR_ADDRESS
  jsr display_hex
  lda #' '
  jsr display_character

  rts


interrupt:
  pha

  lda #IT1
  sta IFR

  inc COUNTER
  bne .done
  inc COUNTER + 1
.done:

  pla
  rti
