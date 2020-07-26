; Routine will flash an LED using busy wait for delay

flash_led:
  sei
  lda PORTA
  eor #FLASH_LED
  sta PORTA
  cli

  lda #<300
  ldx #>300
  jsr sleep_milliseconds
  
  bra flash_led
