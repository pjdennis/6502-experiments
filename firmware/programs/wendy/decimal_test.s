  .include base_config_v1.inc

DISPLAY_STRING_PARAM  = $00 ; 2 bytes

number  = $0200 ; 3 bytes
value   = $0203 ; 3 bytes
mod10   = $0206 ; 1 byte
message = $0207 ; 9 bytes

  .org $2000
  jmp program_entry

  .include display_update_routines_4bit.inc
  .include display_string.inc

program_entry:
  stz number
  stz number + 1
  stz number + 2

outer_loop:
  jsr clear_display

loop:
  lda #DISPLAY_FIRST_LINE
  jsr move_cursor
  jsr show_decimal
  inc number
  bne loop
  inc number + 1
  bne loop
  inc number + 2
  bne loop
  bra outer_loop


show_decimal:

  ; Initialize message to empty string
  stz message

  ; Initialize value to be the number to convert
  lda number
  sta value
  lda number + 1
  sta value + 1
  lda number + 2
  sta value + 2

divide:
  ; Initialize the remainder to be zero
  stz mod10
  clc

  ldx #24
divloop:
  ; Rotate quotient and remainder
  rol value
  rol value + 1
  rol value + 2
  rol mod10

  ; a = dividend - divisor
  sec
  lda mod10
  sbc #10
  bcc ignore_result ; Branch if dividend < divisor
  sta mod10

ignore_result:
  dex
  bne divloop
  rol value
  rol value + 1
  rol value + 2

  ; Shift message
  ldy #8
shift_loop:
  lda message-1,Y
  sta message,Y
  dey
  bne shift_loop

  ; Save value into message
  lda mod10
  clc
  adc #'0'
  sta message

  ; If value != 0 then continue dividing
  lda value
  ora value + 1
  ora value + 2
  bne divide

  lda #<message
  ldx #>message
  jsr display_string

  rts
