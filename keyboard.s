PORTB = $6000
PORTA = $6001
DDRB = $6002
DDRA = $6003

E   = %10000000
RW  = %01000000
RS  = %00100000
KW1 = %00010000
KW0 = %00001000
KR2 = %00000100
KR1 = %00000010
KR0 = %00000001

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

DISPLAY_FIRST_LINE  = $00
DISPLAY_SECOND_LINE = $40

DISPLAY_STRING_PARAM   = $0000


  .org $8000

reset:
  ldx #$ff ; Initialize stack
  txs

  lda #(E | RW | RS) ; Set display control pins on port A to output; keyboard scan pins
  sta DDRA
  lda #%11111111 ; Set all pins on port B to output
  sta DDRB

  lda #(CMD_FUNCTION_SET | %11000) ; Set 8-bit mode; 2-line display; 5x8 font
  jsr display_command

  lda #(CMD_DISPLAY_ON_OFF_CONTROL | %100) ; Display on; cursor off; blink off 
  jsr display_command

  lda #(CMD_ENTRY_MODE_SET | %10) ; Increment and shift cursor; don't shift display 
  jsr display_command

  lda #(CMD_CLEAR_DISPLAY) ; Clear display
  jsr display_command

loop:
  lda #(CMD_SET_DDRAM_ADDRESS | DISPLAY_FIRST_LINE) ; Move to start of first line
  jsr display_command

  ; Display message 1
  lda #<message1
  ldx #>message1
  jsr display_string

;  lda PORTA
;  and #KW0
;  jsr show_bit
;  lda PORTA
;  and #KW1
;  jsr show_bit
;  lda PORTA
;  and #KR0
;  jsr show_bit
;  lda PORTA
;  and #KR1
;  jsr show_bit
;  lda PORTA
;  and #KR2
;  jsr show_bit

  lda #(E | RW | RS | KW0)
  sta DDRA
  lda #KW0
  sta PORTA
  lda PORTA
  and #KR0
  jsr show_bit
  lda #KW0
  sta PORTA
  lda PORTA
  and #KR1
  jsr show_bit
  lda #KW0
  sta PORTA
  lda PORTA
  and #KR2
  jsr show_bit

  lda #(E | RW | RS | KW1)
  sta DDRA
  lda #KW1
  sta PORTA
  lda PORTA
  and #KR0
  jsr show_bit
  lda #KW1
  sta PORTA
  lda PORTA
  and #KR1
  jsr show_bit
  lda #KW1
  sta PORTA
  lda PORTA
  and #KR2
  jsr show_bit

  jmp loop

  ;lda #(CMD_SET_DDRAM_ADDRESS | DISPLAY_SECOND_LINE) ; Move to second line
  ;jsr display_command

message1:
  .asciiz "Raw: "

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

show_bit:
  beq bit_zero
  lda #'1'
  jmp display_character ; tail call
bit_zero:
  lda #'0'
  jmp display_character ; tail call


  .org $fffc
  .word reset
  .word $0000
