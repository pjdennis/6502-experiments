PORTB = $6000
PORTA = $6001
DDRB  = $6002
DDRA  = $6003

; PORTA assignments
BANK_MASK         = %00001111
ILED              = %00010000
;LED              = %00100000
BUTTON            = %00100000
FLASH_LED         = %01000000
SERIAL_IN         = %10000000

BANK_START        = %00000100
BANK_STOP         = %00010000

; PORTB assignments
T1_SQWAVE_OUT     = %10000000
DISPLAY_DATA_MASK = %01111000
E                 = %00000100
RW                = %00000010
RS                = %00000001

BF                = %01000000
DISPLAY_BITS_MASK = (DISPLAY_DATA_MASK | E | RW | RS)

; Include additional definitions
  .include display_parameters.inc
  .include 6522.inc

DISPLAY_STRING_PARAM  = $00 ; 2 bytes
COUNTER               = $02 ; 2 bytes

INTERRUPT_ROUTINE     = $3f00

ROM_DISPLAY_CHARACTER = display_character + ($8000 - $2000) - 3

  .org $2000
  jmp program_entry

  ; Place code for delay_routines at start of page to ensure no page boundary crossings
  ; during timing loops
  .include delay_routines.inc

  .include display_routines.inc
  .include convert_to_hex.inc


program_entry:
  ; Clear the display
  lda #CMD_CLEAR_DISPLAY
  jsr display_command

  lda #<message
  ldx #>message
  jsr display_string

  stz COUNTER
  stz COUNTER + 1

  ldx #0
forever:
  inx
  cpx #10
  bne do_not_flash
  lda PORTA
  eor #ILED
  sta PORTA
  ldx #0
do_not_flash:
  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  lda COUNTER + 1
  jsr display_hex
  lda COUNTER
  jsr display_hex
  lda #200
  jsr delay_10_thousandths
  inc COUNTER
  bne forever
  inc COUNTER + 1
  bra forever  


message: asciiz 'Hello, from ram!'


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


; Vectors
;  .org $fffc
;  .word program_entry
;  .word 0

