; Program will toggle an LED on and off based on a button press
led_control:
  lda PORTA
  and #CONTROL_BUTTON
  beq button_down

  lda #<50
  ldx #>50
  jsr sleep_milliseconds

  bra led_control
button_down:
  sei
  lda PORTA
  eor #CONTROL_LED
  sta PORTA
  cli
led_wait_button:
  ldy #5
led_wait_button_loop:
  lda #<10
  ldx #>10
  jsr sleep_milliseconds

  lda PORTA
  and #CONTROL_BUTTON
  beq led_wait_button
  
  dey
  bne led_wait_button_loop

  bra led_control
led_control_end:
