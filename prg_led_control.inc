; Program will toggle an LED on and off based on a button press

  .ifndef CONTROL_LED_PORT
CONTROL_LED_PORT = PORTA
  .endif

  .ifndef CONTROL_BUTTON_PORT
CONTROL_BUTTON_PORT = PORTA
  .endif


led_control:
  lda CONTROL_BUTTON_PORT
  and #CONTROL_BUTTON
  beq button_down

  lda #<50
  ldx #>50
  jsr sleep_milliseconds

  bra led_control
button_down:
  sei
  lda CONTROL_LED_PORT
  eor #CONTROL_LED
  sta CONTROL_LED_PORT
  cli
led_wait_button:
  ldy #5
led_wait_button_loop:
  lda #<10
  ldx #>10
  jsr sleep_milliseconds

  lda CONTROL_BUTTON_PORT
  and #CONTROL_BUTTON
  beq led_wait_button
  
  dey
  bne led_wait_button_loop

  bra led_control
led_control_end:
