wait_for_not_busy:
  pha
  phx

still_busy:
  lda #DISPLAY_DATA_MASK                   ; - Set display data pins on port B to input
  trb DISPLAY_DATA_PORT + DDR_OFFSET

  lda #RW
  tsb DISPLAY_DATA_PORT                    ; - Set RW (read) flag for reading

  lda #E
  tsb DISPLAY_ENABLE_PORT                  ; - Set E flag to trigger read of first 4 bits
  ldx DISPLAY_DATA_PORT                    ; - Read data value from port
  trb DISPLAY_ENABLE_PORT                  ; - Clear E flag

  tsb DISPLAY_ENABLE_PORT                  ; - Set E flag to trigger read of second 4 bits
  trb DISPLAY_ENABLE_PORT                  ; - Clear E flag

  lda #DISPLAY_BITS_MASK
  trb DISPLAY_DATA_PORT                    ; - Clear the RW flag and set data bits back to 0 ready for next send

  lda #DISPLAY_DATA_MASK
  tsb DISPLAY_DATA_PORT + DDR_OFFSET       ; - Set display data pins on port B back to output

  txa
  and #BF                                  ; Check busy flag
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
  ldx #0                                   ; RS flag not set for command
  bra send_to_display

; On Entry A = Character to send
; On Exit  X, Y preserved
;          A not preserved
display_character:
  .ifdef EXTEND_CHARACTER_SET
  jsr extend_character_set_translate_for_display
  .endif

; Alternate entry point bypasses translation
display_data:
  phx
  ldx #RS                                  ; RS flag set for accessing display memory  
  ; fall through

send_to_display:
  phy
  jsr wait_for_not_busy
  
  pha

  ; Shift lower nybble to the display data location
  .if DISPLAY_DATA_MASK == %11110000
  asl
  asl
  asl
  asl
  .endif
  .if DISPLAY_DATA_MASK == %01111000
  asl
  asl
  asl
  .endif
  .if DISPLAY_DATA_MASK == %00111100
  asl
  asl
  .endif
  .if DISPLAY_DATA_MASK == %00011110
  asl
  .endif

  and #DISPLAY_DATA_MASK
  tay                                      ; Second 4 bits to send are in Y
  pla

  ; Shift upper nybble to the display data location
  .if DISPLAY_DATA_MASK == %00001111
  lsr
  lsr
  lsr
  lsr
  .endif
  .if DISPLAY_DATA_MASK == %00011110
  lsr
  lsr
  lsr
  .endif
  .if DISPLAY_DATA_MASK == %00111100
  lsr
  lsr
  .endif
  .if DISPLAY_DATA_MASK == %01111000
  lsr
  .endif

  and #DISPLAY_DATA_MASK                   ; First 4 bits to send are in A

  tsb DISPLAY_DATA_PORT                    ; - Output the command first 4 bits
  txa                                      ; - Flag for type of command to send is in X
  tsb DISPLAY_DATA_PORT                    ; - Set flag (RS or not) to indicate command vs character
  lda #E
  tsb DISPLAY_ENABLE_PORT                  ; - Set E bit to send instruction
  trb DISPLAY_ENABLE_PORT                  ; - Clear E bit
  lda #DISPLAY_DATA_MASK
  trb DISPLAY_DATA_PORT                    ; - Clear data lines ready for next send

  tya
  tsb DISPLAY_DATA_PORT                    ; - Output the command second 4 bits
  lda #E
  tsb DISPLAY_ENABLE_PORT                  ; - Set E bit to send instruction
  trb DISPLAY_ENABLE_PORT                  ; - Clear E bit
  lda #DISPLAY_BITS_MASK
  trb DISPLAY_DATA_PORT                    ; - Clear data lines and command flags ready for next send

  ply
  plx
  rts


  .include display_update_helpers.inc
