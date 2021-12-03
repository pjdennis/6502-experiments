  .include base_config_v1.inc

DISPLAY_STRING_PARAM  = $00 ; 2 bytes

value = $0200 ; 2 bytes
mod10 = $0202 ; 1 byte
message = $0203 ; 6 bytes

  .org $2000
  jmp program_entry

  .include display_update_routines_4bit.inc
  .include display_string.inc

program_entry:
  jsr clear_display

  ; Initialize message to empty string
  stz message

  ; Initialize value to be the number to convert
  lda number
  sta value
  lda number + 1
  sta value + 1

divide:
  ; Initialize the remainder to be zero
  stz mod10
  clc

  ldx #16
divloop:
  ; Rotate quotient and remainder
  rol value
  rol value + 1
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

  ; Shift message
  ldy #5
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
  bne divide

  lda #<message
  ldx #>message
  jsr display_string

  stp ; Halt the CPU


number: .word 1729
