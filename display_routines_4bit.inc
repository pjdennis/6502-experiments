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

; "Initialization by instruction" sequence per datasheet
reset_display:
  lda #150                                 ; Delay 15ms per datasheet
  jsr delay_10_thousandths

  lda #(CMD_FUNCTION_SET | %10000)         ; Set 8-bit mode
  jsr display_command_8bit_no_wait

  lda #41                                  ; Delay 4.1ms per datasheet
  jsr delay_10_thousandths

  lda #(CMD_FUNCTION_SET | %10000)         ; Set 8-bit mode
  jsr display_command_8bit_no_wait

  lda #1                                   ; Delay 100us per datasheet
  jsr delay_10_thousandths

  lda #(CMD_FUNCTION_SET | %10000)         ; Set 8-bit mode
  jsr display_command_8bit_no_wait

  lda #1                                   ; Wait for at least 37us (execution time for "Function set")
  jsr delay_10_thousandths

  lda #CMD_FUNCTION_SET                    ; Set 4-bit mode
  jsr display_command_8bit_no_wait

  ; Cannot check for busy immediately after setting 4 bit mode since display will not immediately
  ; change from 8 bit to 4 bit for the purposes of reading
  lda #1                                   ; Wait for at least 37us (execution time for "Function set")
  jsr delay_10_thousandths

  lda #(CMD_FUNCTION_SET | %01000)         ; Set 4-bit mode; 2-line display; 5x8 font
  jsr display_command

  lda #(CMD_DISPLAY_ON_OFF_CONTROL | %000) ; Display off; cursor off; blink off 
  jsr display_command

  .ifdef EXTEND_CHARACTER_SET
  jsr extend_character_set_init
  .endif

  jsr clear_display

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
  trb DISPLAY_DATA_PORT                    ; Clear data ready for next send

  rts


  .include display_update_routines_4bit.inc
  .include display_init_helpers.inc
