  .include display_parameters.inc

  .ifndef DISPLAY_DATA_PORT
DISPLAY_DATA_PORT = PORTB
  .endif

  .ifndef DISPLAY_ENABLE_PORT
DISPLAY_ENABLE_PORT = PORTB
  .endif

  .ifndef DISPLAY_BITS
DISPLAY_BITS = 4
  .endif

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

  lda #DISPLAY_DATA_MASK                   ; Set display data pins to input
  trb DISPLAY_DATA_PORT + DDR_OFFSET
  lda #RW                                  ; Set RW (read) flag for reading
  tsb DISPLAY_DATA_PORT
still_busy_8bit:
  lda #E
  tsb DISPLAY_ENABLE_PORT                  ; Set E flag to trigger read
  ldx DISPLAY_DATA_PORT
  trb DISPLAY_ENABLE_PORT                  ; Clear E flag

  txa
  and #BF                                  ; Check busy flag
  bne still_busy_8bit
  ; Not busy
  lda #DISPLAY_BITS_MASK
  trb DISPLAY_DATA_PORT                    ; Clear the RW (read) flag and data bits ready for next send

  lda #DISPLAY_DATA_MASK
  tsb DISPLAY_DATA_PORT + DDR_OFFSET       ; Set display data pins to output

  plx
  pla
  rts


; On input A = command to send
display_command_8bit_no_wait:
  pha                                      ; might not need this
  lda #DISPLAY_DATA_MASK
  trb DISPLAY_DATA_PORT
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

  and #DISPLAY_DATA_MASK
  tsb DISPLAY_DATA_PORT

  lda #E
  tsb DISPLAY_ENABLE_PORT                  ; Set E bit to send instruction
  trb DISPLAY_ENABLE_PORT                  ; Clear E bit

  lda #DISPLAY_DATA_MASK
  trb DISPLAY_ENABLE_PORT                  ; Clear data ready for next send       

  rts


  .include display_update_routines_4bit.inc
  .include display_init_helpers.inc
