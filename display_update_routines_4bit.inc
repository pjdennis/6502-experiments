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


  .include display_update_helpers.inc
