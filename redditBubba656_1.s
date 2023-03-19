CLOCK_FREQ_KHZ    = 5000

PORTB             = $6000
PORTA             = $6001
DDRB              = $6002
DDRA              = $6003
DDR_OFFSET        = 2

; PORTA assignments
BANK_MASK         = %00001111
SD_CSB            = %10000000

BANK_START        = %00000100
BANK_STOP         = %00010000

; PORTB assignments
DISPLAY_DATA_MASK   = %01111000
RW                  = %00000010
RS                  = %00000001
BF                  = %01000000
DISPLAY_BITS_MASK   = (DISPLAY_DATA_MASK | RW | RS)

E                   = %00000100

;16x2 LCD
DISPLAY_WIDTH     = 16
DISPLAY_HEIGHT    = 2
DISPLAY_LAST_LINE = DISPLAY_SECOND_LINE

PORTA_OUT_MASK    = SD_CSB
SD_CS_PORT        = PORTA
PORTB_OUT_MASK    = DISPLAY_BITS_MASK | E

; Display commands
CMD_CLEAR_DISPLAY           = %00000001
CMD_RETURN_HOME             = %00000010
CMD_ENTRY_MODE_SET          = %00000100
CMD_DISPLAY_ON_OFF_CONTROL  = %00001000
CMD_CURSOR_OR_DISPLAY_SHIFT = %00010000
CMD_FUNCTION_SET            = %00100000
CMD_SET_CGRAM_ADDRESS       = %01000000
CMD_SET_DDRAM_ADDRESS       = %10000000

; Display command bits
CMD_PARAM_DISPLAY_ON        = %00000100
CMD_PARAM_CURSOR_ON         = %00000010
CMD_PARAM_CURSOR_BLINK      = %00000001

; Display paramters
DISPLAY_FIRST_LINE  = $00
DISPLAY_SECOND_LINE = $40

  .org $2000
  jmp program_entry

  ; Place delay_routines at start of page to ensure no page boundary crossings during timing loops
  .include delay_routines.inc

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

  jsr clear_display

  rts


; On input A = command to send
display_command_8bit_no_wait:
  pha                                      ; might not need this
  lda #DISPLAY_DATA_MASK
  trb PORTB
  pla

  ; Shift upper nybble to the display data location
  lsr

  and #DISPLAY_DATA_MASK
  tsb PORTB
  lda #E
  tsb PORTB                                ; Set E bit to send instruction
  trb PORTB                                ; Clear E bit

  lda #DISPLAY_DATA_MASK
  trb PORTB                                ; Clear data ready for next send

  rts


wait_for_not_busy:
  pha
  phx

still_busy:
  lda #DISPLAY_DATA_MASK                   ; - Set display data pins on port B to input
  trb DDRB                               

  lda #RW
  tsb PORTB                                ; - Set RW (read) flag for reading

  lda #E
  tsb PORTB                                ; - Set E flag to trigger read of first 4 bits
  ldx PORTB                                ; - Read data value from port
  trb PORTB                                ; - Clear E flag

  tsb PORTB                                ; - Set E flag to trigger read of second 4 bits
  trb PORTB                                ; - Clear E flag

  lda #DISPLAY_BITS_MASK
  trb PORTB                                ; - Clear the RW flag and set data bits back to 0 ready for next send

  lda #DISPLAY_DATA_MASK
  tsb DDRB                                 ; - Set display data pins on port B back to output

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
  phx
  ldx #RS                                  ; RS flag set for accessing display memory  
  ; fall through

send_to_display:
  phy
  jsr wait_for_not_busy
  
  pha

  ; Shift lower nybble to the display data location
  asl
  asl
  asl

  and #DISPLAY_DATA_MASK
  tay                                      ; Second 4 bits to send are in Y
  pla

  ; Shift upper nybble to the display data location
  lsr

  and #DISPLAY_DATA_MASK                   ; First 4 bits to send are in A

  tsb PORTB                                ; - Output the command first 4 bits
  txa                                      ; - Flag for type of command to send is in X
  tsb PORTB                                ; - Set flag (RS or not) to indicate command vs character
  lda #E
  tsb PORTB                                ; - Set E bit to send instruction
  trb PORTB                                ; - Clear E bit
  lda #DISPLAY_DATA_MASK
  trb PORTB                                ; - Clear data lines ready for next send

  tya
  tsb PORTB                                ; - Output the command second 4 bits
  lda #E
  tsb PORTB                                ; - Set E bit to send instruction
  trb PORTB                                ; - Clear E bit
  lda #DISPLAY_BITS_MASK
  trb PORTB                                ; - Clear data lines and command flags ready for next send

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


; On exit A, X, Y preserved
display_space:
  pha
  lda #' '
  jsr display_character
  pla
  rts


; On exit A, X, Y preserved
display_cursor_off:
  pha
  lda #(CMD_DISPLAY_ON_OFF_CONTROL | CMD_PARAM_DISPLAY_ON) ; Display on; cursor off
  jsr display_command
  pla
  rts


; On exit A, X, Y preserved
display_cursor_on:
  pha
  lda #(CMD_DISPLAY_ON_OFF_CONTROL | CMD_PARAM_DISPLAY_ON | CMD_PARAM_CURSOR_ON)
  jsr display_command
  pla
  rts


reset_and_enable_display_no_cursor:  
  jsr reset_display

  lda #(CMD_ENTRY_MODE_SET | %10)          ; Increment and shift cursor; don't shift display 
  jsr display_command

  lda #(CMD_DISPLAY_ON_OFF_CONTROL | CMD_PARAM_DISPLAY_ON) ; Display on; cursor off; blink off
  jsr display_command

  rts


program_entry:
  ldx #$ff                                 ; Initialize stack
  txs

  lda #0                                   ; Initialize status flags
  pha
  plp

  ; Initialize 6522 port A (memory banking control)
  lda #(BANK_START | SD_CSB)
  sta PORTA
  lda #PORTA_OUT_MASK                      ; Set pin direction on port A
  sta DDRA

  ; Initialize 6522 port B (display control)
  lda #0
  sta PORTB
  lda #PORTB_OUT_MASK                      ; Set pin direction on port B
  sta DDRB

  ; Initialize display
  jsr reset_and_enable_display_no_cursor

  lda #'X'
  jsr display_character
forever:
  bra forever
