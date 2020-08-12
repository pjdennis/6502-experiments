  .include display_parameters.inc

reset_and_enable_display_no_cursor:  
  jsr reset_display

  lda #(CMD_ENTRY_MODE_SET | %10)          ; Increment and shift cursor; don't shift display 
  jsr display_command

  lda #(CMD_DISPLAY_ON_OFF_CONTROL | %100) ; Display on; cursor off; blink off 
  jsr display_command

  rts


; Reset sequence per datasheet
reset_display:
  lda #150
  jsr delay_10_thousandths

  lda #(CMD_FUNCTION_SET | %10000)         ; Set 8-bit mode
  jsr display_command_8bit_no_wait

  lda #41
  jsr delay_10_thousandths

  lda #(CMD_FUNCTION_SET | %10000)         ; Set 8-bit mode
  jsr display_command_8bit_no_wait

  lda #1
  jsr delay_10_thousandths

  lda #(CMD_FUNCTION_SET | %10000)         ; Set 8-bit mode
  jsr display_command_8bit_no_wait

  jsr wait_for_not_busy_8bit

  lda #CMD_FUNCTION_SET                    ; Set 4-bit mode
  jsr display_command_8bit_no_wait

  lda #(CMD_FUNCTION_SET | %01000)         ; Set 4-bit mode; 2-line display; 5x8 font
  jsr display_command

  lda #(CMD_DISPLAY_ON_OFF_CONTROL | %000) ; Display off; cursor off; blink off 
  jsr display_command

  jsr clear_display

  rts


wait_for_not_busy_8bit:
  pha
  phx

  lda #DISPLAY_DATA_MASK ; Set display data pins to input
  trb DDRB
  lda #RW                ; Set RW (read) flag for reading
  tsb PORTB
still_busy_8bit:
  lda #E
  tsb PORTB              ; Set E flag to trigger read
  ldx PORTB
  trb PORTB              ; Clear E flag

  txa
  and #BF                ; Check busy flag
  bne still_busy_8bit
  ; Not busy
  lda #DISPLAY_BITS_MASK
  trb PORTB              ; Clear the RW (read) flag and data bits ready for next send

  lda #DISPLAY_DATA_MASK 
  tsb DDRB               ; Set display data pins to output

  plx
  pla
  rts


; On input A = command to send
display_command_8bit_no_wait:
  pha  ; might not need this
  lda #DISPLAY_DATA_MASK
  trb PORTB
  pla

  lsr             ; Shift to match display data location
  and #DISPLAY_DATA_MASK
  tsb PORTB

  lda #E
  tsb PORTB       ; Set E bit to send instruction
  trb PORTB       ; Clear E bit

  lda #DISPLAY_DATA_MASK
  trb PORTB       ; Clear data ready for next send       

  rts

  .include display_update_routines.inc
  .include display_hex.inc
