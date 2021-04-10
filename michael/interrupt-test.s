PORTB = $6000
PORTA = $6001
DDRB  = $6002
DDRA  = $6003
ACR   = $600B
PCR   = $600C
IFR   = $600D
IER   = $600E

E    = %10000000  ; Display enable
RW   = %01000000  ; Display read/write
RS   = %00100000  ; Display register select

SOEB = %00010000  ; Shift register output enable (active low)

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

DISPLAY_STRING_PARAM    = $0000 ; 2 bytes
CONSOLE_CHARACTER_COUNT = $0002 ; 1 byte
SIMPLE_BUFFER_WRITE_PTR = $0003 ; 1 byte
SIMPLE_BUFFER_READ_PTR  = $0004 ; 1 byte 

CONSOLE_TEXT            = $0200 ; CONSOLE_LENGTH (32) bytes
SIMPLE_BUFFER           = $0300 ; 256 bytes

  .org $8000

  .include ../full_screen_console.inc
  .include ../simple_buffer.inc

reset:
  ldx #$ff ; Initialize stack
  txs

  lda #SOEB
  tsb DDRA
  tsb PORTA

  jsr initialize_display

  jsr console_initialize
  jsr simple_buffer_initialize

  lda #%00000110  ; CA2 independent interrupt rising edge
  sta PCR

  lda #%10000001  ; Enable CA2 interrupt
  sta IER

  cli

show_simple_buffer_loop:
  jsr simple_buffer_read
  bcs show_simple_buffer_loop
show_simple_buffer_copy_loop:
  jsr convert_to_hex
  jsr console_print_character
  txa
  jsr console_print_character
  jsr simple_buffer_read
  bcc show_simple_buffer_copy_loop
  jsr console_show
  bra show_simple_buffer_loop


interrupt:
  pha
  phx

  lda #%00000001  ; Clear the CA2 interrupt
  sta IFR

  ldx DDRB        ; Save DDRB to X

  lda #%00000000
  sta DDRB        ; Set PORTB to input

  lda #SOEB
  trb PORTA       ; Enable shift register output

  lda PORTB
  jsr simple_buffer_write

  lda #SOEB
  tsb PORTA       ; Disable shift register output

  stx DDRB        ; Restore DDRB from X

  plx
  pla
  rti


message:
  .asciiz "Value: "


wait_for_not_busy:
  pha
  phx
  lda #%00000000 ; Set all pins on port B to input
  sta DDRB
  lda #RW
  tsb PORTA      ; Set RW for reading
busy:
  lda #E         ; Enable flag
  sei
  tsb PORTA
  ldx PORTB
  trb PORTA
  cli
  txa
  and #%10000000
  bne busy
  lda #RW
  trb PORTA
  lda #%11111111 ; Set all pins on port B to output
  sta DDRB
  plx
  pla
  rts


display_command:
  jsr wait_for_not_busy
  sta PORTB
  lda #E         ; Enable bit
  sei
  tsb PORTA
  trb PORTA
  cli
  rts


display_character:
  jsr wait_for_not_busy
  sta PORTB
  lda #RS        ; Register select bit
  tsb PORTA      ; Select the data register
  lda #E         ; Enable bit
  sei
  tsb PORTA
  trb PORTA
  cli
  lda #RS        ; Register select bit
  trb PORTA      ; Select the instruction register
  rts


initialize_display:
  lda #(E | RW | RS) ; Set display control pins on port A to output
  tsb DDRA
  trb PORTA

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

  rts


; On entry A = location to move to
; On exit  X, Y preserved
;          A not preserved 
move_cursor:
  ora #CMD_SET_DDRAM_ADDRESS
  jsr display_command
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


; On entry A = value to convert
; On exit  X = low result
;          A = high result
;          Y is preserved
convert_to_hex:
  pha
  and #$0f
  cmp #10
  bcs convert_to_hex_character_low
  adc #'0'
  bra convert_to_hex_done_low
convert_to_hex_character_low:
  clc
  adc #('A' - 10)
convert_to_hex_done_low:
  tax

  pla
  lsr
  lsr
  lsr
  lsr
  cmp #10
  bcs convert_to_hex_character_high
  adc #'0'
  rts
convert_to_hex_character_high:
  clc
  adc #('A' - 10)
  rts


; On entry A = byte to display in hex
; On exit  A, X, Y are preserved
display_hex:
  pha
  phx
  jsr convert_to_hex
  jsr display_character
  txa
  jsr display_character
  plx
  pla
  rts


  .org $fffc
  .word reset
  .word interrupt
