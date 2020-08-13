  .include base_config_v1.inc

BUTTON          = %00100000

D_S_I_P         = $00

  .org $2000
  jmp program_entry

  .include display_update_routines.inc
  .include display_hex.inc
  .include display_binary.inc
  .include display_string_immediate.inc
  .include delay_routines.inc

program_entry:
  lda #BUTTON
  trb DDRA

  jsr display_string_immediate
  asciiz "Shift in..."

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor

  lda #%10010101
  jsr display_binary


  jmp stop_here


  ldx #0
repeat:
  jsr wait_for_button_down

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  txa
  jsr display_hex

  jsr send_serial

  jsr wait_for_button_up

  inx
  bra repeat

wait:
  bra wait


send_serial_with_delay:
  jsr send_serial
  jsr delay
  rts


send_serial:
  pha
  ;lda #$00
  ;sta T2CL
  ;lda #ACR_SR_OUT_T2
  lda #ACR_SR_OUT_CK
  sta ACR
  pla
  sta SR
  rts


delay:
  pha
  phx

  ldx #20
  lda #100
delay_loop:
  jsr delay_10_thousandths
  dex
  bne delay_loop

  plx
  pla
  rts


short_delay:
  pha
  phx

  ldx #2
  lda #100
short_delay_loop:
  jsr delay_10_thousandths
  dex
  bne short_delay_loop

  plx
  pla
  rts


wait_for_button_down:
  lda PORTA
  and #BUTTON
  bne wait_for_button_down
  rts


wait_for_button_up:
  ldy #5
wait_for_button_up_loop:
  lda #100
  jsr delay_10_thousandths
  lda PORTA
  and #BUTTON
  beq wait_for_button_up
  dey
  bne wait_for_button_up_loop
  rts


stop_here:
  bra stop_here
