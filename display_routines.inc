reset_and_enable_display_no_cursor:  
  jsr reset_display

  lda #(CMD_ENTRY_MODE_SET | %10)          ; Increment and shift cursor; don't shift display 
  jsr display_command

  lda #(CMD_DISPLAY_ON_OFF_CONTROL | %100) ; Display on; cursor off; blink off 
  jsr display_command
  rts

reset_display:
  ; Reset sequence per datasheet

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

  lda #(CMD_CLEAR_DISPLAY)                 ; Clear display
  jsr display_command

  rts


wait_for_not_busy_8bit:
  pha

  lda DDRB
  and #(~DISPLAY_DATA_MASK & $ff) ; Set display data pins to input
  sta DDRB

still_busy_8bit:
  lda PORTB
  and #(~DISPLAY_BITS_MASK & $ff)
  ora #RW         ; Set RW flag for reading
  sta PORTB

  ora #E          ; Set E flag to trigger read
  sta PORTB

  lda PORTB
  and #BF         ; Check busy flag
  bne still_busy_8bit

  lda PORTB
  and #(~E & $ff) ; Clear E flag
  sta PORTB

  lda DDRB
  ora #DISPLAY_DATA_MASK ; Set display data pins to output
  sta DDRB

  pla

  rts


display_command_8bit_no_wait:
  lsr             ; Shift to match display data location
  and #DISPLAY_DATA_MASK
  sta DISPLAY_SCRATCH
  lda PORTB
  and #(~DISPLAY_BITS_MASK & $ff)
  ora DISPLAY_SCRATCH
  sta PORTB
  ora #E          ; Set E bit to send instruction
  sta PORTB
  and #(~E & $ff) ; Clear E bit
  sta PORTB
  rts


wait_for_not_busy:
  pha
  txa
  pha

  ; Set data direction for display data pins to input
  sei
  lda DDRB
  and #(~DISPLAY_DATA_MASK & $ff) ; Set display data pins on port B to input
  sta DDRB
  cli

still_busy:

  sei
  ; Read the first 4 bits
  lda PORTB
  and #(~DISPLAY_BITS_MASK & $ff)
  ora #RW         ; Set RW flag for reading
  sta PORTB
  ora #E          ; Set E flag to trigger read
  sta PORTB
  ldx PORTB

  ; Read second 4 bits
  and #(~E & $ff) ; Clear the E flag
  sta PORTB
  ora #E          ; Set E flag to trigger read
  sta PORTB
  ora #(~E & $ff) ; Clear the E flag
  cli

  txa
  and #BF         ; Check busy flag
  bne still_busy

  ; Restore data direction register
  sei
  lda DDRB
  ora #DISPLAY_DATA_MASK ; Set display data pins on port B back to output
  sta DDRB
  cli

  pla
  tax
  pla
  rts


display_command:
  jsr wait_for_not_busy
  pha
  lsr ; Shift to match display data location
  and #DISPLAY_DATA_MASK
  sta DISPLAY_SCRATCH

  sei
  lda PORTB
  and #(~DISPLAY_BITS_MASK & $ff)
  ora DISPLAY_SCRATCH
  sta PORTB
  ora #E          ; Set E bit to send instruction
  sta PORTB
  and #(~E & $ff) ; Clear E bit
  sta PORTB

  pla
  asl ; shift lower byte to display data location
  asl
  asl
  and #DISPLAY_DATA_MASK
  sta DISPLAY_SCRATCH

  lda PORTB
  and #(~DISPLAY_BITS_MASK & $ff)
  ora DISPLAY_SCRATCH
  sta PORTB
  ora #E          ; Set E bit to send instruction
  sta PORTB
  and #(~E & $ff) ; Clear E bit
  sta PORTB
  cli

  rts


display_character:
  jsr wait_for_not_busy
  pha
  lsr ; Shift to match display data location
  and #DISPLAY_DATA_MASK
  sta DISPLAY_SCRATCH

  sei
  lda PORTB
  and #(~DISPLAY_BITS_MASK & $ff)
  ora DISPLAY_SCRATCH
  ora #RS         ; Set RS bit
  sta PORTB
  ora #E          ; Set E bit to send instruction
  sta PORTB
  and #(~E & $ff) ; Clear E bit
  sta PORTB

  pla
  asl ; Shift to match display data location
  asl
  asl
  and #DISPLAY_DATA_MASK
  sta DISPLAY_SCRATCH

  lda PORTB
  and #(~DISPLAY_BITS_MASK & $ff)
  ora DISPLAY_SCRATCH
  ora #RS         ; Set RS bit
  sta PORTB
  ora #E          ; Set E bit to send instruction
  sta PORTB
  and #(~E & $ff) ; Clear E bit
  sta PORTB
  cli

  rts
