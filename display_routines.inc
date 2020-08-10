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


wait_for_not_busy:
  pha
  phx

still_busy:
  lda #DISPLAY_DATA_MASK ; - Set display data pins on port B to input
  trb DDRB

  lda #RW
  tsb PORTB              ; - Set RW (read) flag for reading

  lda #E
  tsb PORTB              ; - Set E flag to trigger read of first 4 bits
  ldx PORTB              ; - Read data value from PORTB
  trb PORTB              ; - Clear E flag

  tsb PORTB              ; - Set E flag to trigger read of second 4 bits
  trb PORTB              ; - Clear E flag

  lda #DISPLAY_BITS_MASK
  trb PORTB              ; - Clear the RW flag and set data bits back to 0 ready for next send

  lda #DISPLAY_DATA_MASK
  tsb DDRB               ; - Set display data pins on port B back to output

  txa
  and #BF                ; Check busy flag
  bne still_busy
  ; Not busy

  plx
  pla
  rts


; On Entry A = Command to send
; On Exit  X, Y preserved
;          A not preserved
display_command:
  phx
  ldx #0                 ; RS flag not set for command
  bra send_to_display

; On Entry A = Character to send
; On Exit  X, Y preserved
;          A not preserved
display_character:
  phx
  ldx #RS                ; RS flag set for accessing display memory  
  ; fall through

send_to_display:
  phy
  jsr wait_for_not_busy
  
  pha
  asl                    ; Shift lower byte to display data location
  asl
  asl
  and #DISPLAY_DATA_MASK
  tay                    ; Second 4 bits to send are in Y
  pla

  lsr                    ; Shift upper byte to display data location
  and #DISPLAY_DATA_MASK ; First 4 bits to send are in A

  tsb PORTB              ; - Output the command first 4 bits
  txa                    ; - Flag for type of command to send is in X
  tsb PORTB              ; - Set flag (RS or not) to indicate command vs character
  lda #E                 ;
  tsb PORTB              ; - Set E bit to send instruction
  trb PORTB              ; - Clear E bit
  lda #DISPLAY_DATA_MASK ;
  trb PORTB              ; - Clear data lines ready for next send
                         ;
  tya                    ;
  tsb PORTB              ; - Output the command second 4 bits
  lda #E                 ;
  tsb PORTB              ; - Set E bit to send instruction
  trb PORTB              ; - Clear E bit
  lda #DISPLAY_BITS_MASK ;
  trb PORTB              ; - Clear data lines and command flags ready for next send

  ply
  plx
  rts


; On exit A, X, Y preserved
clear_display:
  pha
  lda #CMD_CLEAR_DISPLAY     ; clear display
  jsr display_command
  pla
  rts

; On entry A = location to move to
; On exit  X, Y preserved
;          A not preserved 
move_cursor:
  ora #CMD_SET_DDRAM_ADDRESS
  jmp display_command        ; tail call


; On entry A = byte to display in hex
; On exit  X, Y are preserved
;          A is not preserved
display_hex:
  phx
  jsr convert_to_hex
  jsr display_character
  txa
  jsr display_character
  plx
  rts

