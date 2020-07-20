PORTB = $6000
PORTA = $6001
DDRB = $6002
DDRA = $6003

E  = %10000000
RW = %01000000
RS = %00100000

SET   = $FF
UNSET = $00

CMD_CLEAR_DISPLAY           = %00000001
CMD_RETURN_HOME             = %00000010
CMD_ENTRY_MODE_SET          = %00000100
CMD_DISPLAY_ON_OFF_CONTROL  = %00001000
CMD_CURSOR_OR_DISPLAY_SHIFT = %00010000
CMD_FUNCTION_SET            = %00100000
CMD_SET_CGRAM_ADDRESS       = %01000000
CMD_SET_DDRAM_ADDRESS       = %10000000

PRM_FUNCTION_SET_INTERFACE_DATA_LENGTH   = %00010000
PRM_FUNCTION_SET_NUMBER_OF_DISPLAY_LINES = %00001000
PRM_FUNCTION_SET_CHARACTER_FONT          = %00000100

VAL_FUNCTION_SET_INTERFACE_DATA_LENGTH_8_BIT = SET
VAL_FUNCTION_SET_INTERFACE_DATA_LENGTH_4_BIT = UNSET
VAL_FUNCTION_SET_NUMBER_OF_DISPLAY_LINES_2   = SET
VAL_FUNCTION_SET_NUMBER_OF_DISPLAY_LINES_1   = UNSET
VAL_FUNCTION_SET_CHARACTER_FONT_5x10         = SET
VAL_FUNCTION_SET_CHARACTER_FONT_5x8          = UNSET

DISPLAY_FIRST_LINE  = $00
DISPLAY_SECOND_LINE = $40

DISPLAY_STRING_PARAM = $0000

  .org $8000

reset:
  ldx #$ff ; Initialize stack
  txs

  lda #(E | RW | RS) ; Set display control pins on port A to output
  sta DDRA
  lda #%11111111 ; Set all pins on port B to output
  sta DDRB

  lda #(CMD_FUNCTION_SET | %11000) ; Set 8-bit mode; 2-line display; 5x8 font
  jsr display_command

  lda #(CMD_DISPLAY_ON_OFF_CONTROL | %110) ; Display on; cursor on; blink off 
  jsr display_command

  lda #(CMD_ENTRY_MODE_SET | %10) ; Increment and shift cursor; don't shift display 
  jsr display_command

  lda #(CMD_CLEAR_DISPLAY) ; Clear display
  jsr display_command

  ; Display first message
  lda #<message1
  ldx #>message1
  jsr display_string

  lda #(CMD_SET_DDRAM_ADDRESS | DISPLAY_SECOND_LINE) ; Move to second line
  jsr display_command

  ; Display second message
  lda #<message2
  ldx #>message2
  jsr display_string

loop:
  jmp loop

message1:
  .asciiz "Hello, World!"

message2:
  .asciiz "Goodbye!"

wait_for_not_busy:
  pha
  lda #%00000000 ; Set all pins on port B to input
  sta DDRB
  lda #RW
  sta PORTA
  lda #(RW | E)  ; Set RW and E to enable reading
  sta PORTA
busy:
  lda PORTB
  and #%10000000
  bne busy

  lda #RW
  sta PORTA
  lda #%11111111 ; Set all pins on port B to output
  sta DDRB
  pla
  rts

display_command:
  jsr wait_for_not_busy
  sta PORTB
  lda #0         ; Clear RS/RW/E bits
  sta PORTA
  lda #E         ; Set E bit to send instruction
  sta PORTA
  lda #0         ; Clear RS/RW/E bits
  sta PORTA
  rts

display_character:
  jsr wait_for_not_busy
  sta PORTB
  lda #RS        ; Set RS bit
  sta PORTA
  lda #(RS | E)  ; Set RS and E bit to send instruction
  sta PORTA
  lda #RS        ; Set RS bit
  sta PORTA
  rts

display_string:
  sta DISPLAY_STRING_PARAM
  stx DISPLAY_STRING_PARAM + 1
  ldy #0
print_loop:
  lda (DISPLAY_STRING_PARAM),Y
  beq done_printing
  jsr display_character
  iny
  jmp print_loop
done_printing:
  rts

  .org $fffc
  .word reset
  .word $0000
