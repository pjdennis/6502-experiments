  .ifndef DISPLAY_DO_NOT_DISABLE_INTERRUPTS
DISPLAY_DO_NOT_DISABLE_INTERRUPTS = 0
  .endif

wait_for_not_busy:
  pha
  phx
  lda #%00000000 ; Set all pins on port B to input
  sta DDRB
  lda #RW
  tsb PORTA      ; Set RW for reading
busy:
  lda #E         ; Enable flag
  .ifeq DISPLAY_DO_NOT_DISABLE_INTERRUPTS
  sei
  .endif
  tsb PORTA
  ldx PORTB
  trb PORTA
  .ifeq DISPLAY_DO_NOT_DISABLE_INTERRUPTS
  cli
  .endif
  txa
  and #%10000000
  bne busy
  lda #RW
  trb PORTA
  lda #%11111111 ; Set all pins on port B to output
  sta DDRB
  plx
  pla
  rts


; On Entry A = Command to send
; On Exit  X, Y preserved
;          A not preserved
display_command:
  jsr wait_for_not_busy
  sta PORTB
  lda #E         ; Enable bit
  .ifeq DISPLAY_DO_NOT_DISABLE_INTERRUPTS
  sei
  .endif
  tsb PORTA
  trb PORTA
  .ifeq DISPLAY_DO_NOT_DISABLE_INTERRUPTS
  cli
  .endif
  rts


; On Entry A = Character to send
; On Exit  X, Y preserved
;          A not preserved
display_character:
  jsr wait_for_not_busy
  sta PORTB
  lda #RS        ; Register select bit
  tsb PORTA      ; Select the data register
  lda #E         ; Enable bit
  .ifeq DISPLAY_DO_NOT_DISABLE_INTERRUPTS
  sei
  .endif
  tsb PORTA
  trb PORTA
  .ifeq DISPLAY_DO_NOT_DISABLE_INTERRUPTS
  cli
  .endif
  lda #RS        ; Register select bit
  trb PORTA      ; Select the instruction register
  rts


  .include display_update_helpers.inc 
