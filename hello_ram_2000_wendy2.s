  .include base_config_wendy2.inc

DISPLAY_STRING_PARAM  = $00 ; 2 bytes
COUNTER               = $02 ; 2 bytes

  .org $2000
  jmp program_entry

  ; Place code for delay_routines at start of page to ensure no page boundary crossings
  ; during timing loops
  .include delay_routines.inc

  .include display_routines_4bit.inc
  .include display_hex.inc


program_entry:
  jsr clear_display

  lda #<message
  ldx #>message
  jsr display_string

  stz COUNTER
  stz COUNTER + 1
forever:
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


message: asciiz 'Hello, from ram'


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
