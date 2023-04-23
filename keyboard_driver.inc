; Requires:
; KB_BUFFER_INITIALIZE - funciton to initialize the keyboard buffer
; KB_BUFFER_WRITE      - function to call to write to keyboard buffer
; KB_BUFFER_READ       - function to call to read from keyboard buffer
; copy_memory and CP_M_* parameter locations

keyboard_initialize:
  jsr KB_BUFFER_INITIALIZE

  ; Initialize Keyboard decode state
  stz KEYBOARD_DECODE_STATE
  stz KEYBOARD_MODIFIER_STATE
  stz KEYBOARD_LOCK_STATE

  ; Relocate the interrupt handler. The EEPROM has a fixed address, INTERRUPT_ROUTINE
  ; for the interrupt routine so copy the handler there
  lda #<INTERRUPT_ROUTINE
  sta CP_M_DEST_P
  lda #>INTERRUPT_ROUTINE
  sta CP_M_DEST_P + 1
  lda #<interrupt
  sta CP_M_SRC_P
  lda #>interrupt
  sta CP_M_SRC_P + 1
  lda #<(interrupt_end - interrupt)
  sta CP_M_LEN
  lda #>(interrupt_end - interrupt)
  sta CP_M_LEN + 1
  jsr copy_memory

  ; Initialize flags
  stz KEYBOARD_RECEIVING
  stz SENDING_TO_KEYBOARD
  stz ACK_RECEIVED

  ; Set up interrupts for detecting start of receipt of byte from keyboard
  lda #PCR_CA2_IND_NEG_E
  sta PCR

  lda #%10000001  ; Enable CA2 interrupt
  sta IER

  ; Enable interrupts so we start recieving data from the keyboard
  cli

  ; Initialize keyboard
  lda #KB_COMMAND_ENABLE
  jsr keyboard_send_command

  lda #KB_COMMAND_SET_TYPEMATIC
  jsr keyboard_send_command

  lda #KEYBOARD_RATE_30_0_CPS | KEYBOARD_DELAY_0_50_S
  jsr keyboard_send_command

  lda #0
  jsr keyboard_set_leds

  rts
