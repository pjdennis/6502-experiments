PORTB = $6000
PORTA = $6001
DDRB = $6002
DDRA = $6003

E  = %00001000
RW = %00000100
RS = %00000010

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
CREATE_CHARACTER_PARAM = $0002

CHARACTER_PD = 1

  .org $8000

reset:
  ldx #$ff ; Initialize stack
  txs

  lda #0; Set all pins on port A to input
  sta DDRA
  lda #(%11110000 | E | RW | RS) ; Set display controp pins and data pins on port B to output
  sta DDRB

  lda #0
  sta PORTB

  ; Display reset sequence
  lda #150
  jsr delay_10_thousandths
  lda #(CMD_FUNCTION_SET | %10000) ; Set 8-bit mode
  jsr single_part_display_command
  lda #41
  jsr delay_10_thousandths
  lda #(CMD_FUNCTION_SET | %10000) ; Set 8-bit mode
  jsr single_part_display_command
  lda #1
  jsr delay_10_thousandths
  lda #(CMD_FUNCTION_SET | %10000) ; Set 8-bit mode
  jsr single_part_display_command
  lda #1
  jsr delay_10_thousandths
  lda #CMD_FUNCTION_SET            ; Set 4-bit mode
  jsr single_part_display_command

  lda #(CMD_FUNCTION_SET | %01000)         ; Set 4-bit mode; 2-line display; 5x8 font
  jsr display_command

  lda #(CMD_DISPLAY_ON_OFF_CONTROL | %110) ; Display on; cursor on; blink off 
  jsr display_command

  lda #(CMD_ENTRY_MODE_SET | %10)          ; Increment and shift cursor; don't shift display 
  jsr display_command

  lda #(CMD_CLEAR_DISPLAY)                 ; Clear display
  jsr display_command

  ; Create character
  ;lda #<character_pd
  ;ldx #>character_pd
  ;ldy #CHARACTER_PD
  ;jsr create_character

  lda #(CMD_SET_DDRAM_ADDRESS | DISPLAY_FIRST_LINE) ; Move to first line
  jsr display_command

  ; Display message 1
  lda #<message1
  ldx #>message1
  jsr display_string

  lda #(CMD_SET_DDRAM_ADDRESS | DISPLAY_SECOND_LINE) ; Move to second line
  jsr display_command

  ;lda #CHARACTER_PD ; Custom character 1
  ;jsr display_character 

  ;lda #%10111100
  ;jsr display_character

  ; Display message 2
  lda #<message2
  ldx #>message2
  jsr display_string

loop:
  jmp loop

message1:
  .asciiz "Hello, World!"

message2:
  .asciiz " Goodbye!"

wait_for_not_busy:
  pha
  txa
  pha

  ldx #0
busy:
  nop
  nop
  dex
  bne busy

  pla
  tax
  pla
  rts

single_part_display_command:
  sta PORTB
  ora #E         ; Set E bit to send instruction
  sta PORTB
  and #(~E)      ; Clear E bit
  sta PORTB
  rts

display_command:
  jsr wait_for_not_busy
  pha
  and #%11110000

  sta PORTB
  ora #E         ; Set E bit to send instruction
  sta PORTB
  and #(~E)      ; Clear E bit
  sta PORTB

  pla
  asl
  asl
  asl
  asl

  sta PORTB
  ora #E         ; Set E bit to send instruction
  sta PORTB
  and #(~E)      ; Clear E bit
  sta PORTB

  rts

display_character:
  jsr wait_for_not_busy
  pha
  and #%11110000

  ora #RS        ; Set RS bit
  sta PORTB
  ora #E         ; Set E bit to send instruction
  sta PORTB
  and #(~E)      ; Clear E bit
  sta PORTB

  pla
  asl
  asl
  asl
  asl

  ora #RS        ; Set RS bit
  sta PORTB
  ora #E         ; Set E bit to send instruction
  sta PORTB
  and #(~E)      ; Clear E bit
  sta PORTB

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

;On entry A = low source address
;         X = high byte source address
;         Y = character number
create_character:
  sta CREATE_CHARACTER_PARAM
  stx CREATE_CHARACTER_PARAM + 1

  tya
  asl
  asl
  asl
  ora #CMD_SET_CGRAM_ADDRESS
  jsr display_command

  ldy #0
create_loop:
  lda (CREATE_CHARACTER_PARAM),Y
  jsr display_character

  iny
  cpy #8
  bne create_loop

  rts

character_pd:
  .byte %11000
  .byte %10100
  .byte %11001
  .byte %10001
  .byte %10011
  .byte %00101
  .byte %00011
  .byte %00000


  .org $ff00 ; Place code at start of page to ensure no page boundary crossings during timing loops

delay_10_thousandths:
  tax
outer_delay:       ; looking to have 100 cycles per iteration
  beq delay_done   ; 2 cycles
  
  ; 9 cycles outside of inner loop (excluding extra delay)
  ; need total of 100 - 9 = 91 extra cycles 
  ; 91 / 5 = 18.2 iterations
  ; 18 iterations = 17 * 5 + 4 = 89 cycles
  ; extra delay = 91 - 89 = 2 cycles
  nop              ; 2 cycles (extra delay)
  ldy #18          ; 2 cycles
inner_delay:       ; Per iteration: 5 cycles; 4 on last
  dey              ; 2 cycles
  bne inner_delay  ; 3 cycles

  dex              ; 2 cycles
  jmp outer_delay  ; 3 cycles
delay_done:
  rts

  .org $fffc
  .word reset
  .word $0000
