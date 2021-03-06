D_S_I_P       = $00   ; 2 bytes

V  = $02
X1 = $03
X2 = $04
X3 = $05


TEST_LOCATION = $fe00

  .org $4000
  jmp program_entry

  .include base_config_wendy2c.inc
  .include display_update_routines.inc
  .include display_string_immediate.inc
  .include display_hex.inc

program_entry:
; Program code goes here

  lda #BANK_MASK
  trb BANK_PORT

  stz X1
  stz X2
  stz X3

  jsr display_string_immediate
  .asciiz "Before: "
  ldx TEST_LOCATION

  txa
  jsr display_hex

  inx
  stx V

  ; Update EEPROM data
  lda #$aa
  sta $8000 + $5555

  lda #$55
  sta $8000 + $2aaa

  lda #$a0
  sta $8000 + $5555

  txa
  sta TEST_LOCATION

  lda TEST_LOCATION
  sta X1

  lda TEST_LOCATION
  sta X2

  lda TEST_LOCATION
  sta X3

wait_for_completion_loop:
  lda TEST_LOCATION
  cmp V
  bne wait_for_completion_loop

completed:

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  jsr display_string_immediate
  .asciiz " After: "
  lda TEST_LOCATION
  jsr display_hex

  lda X1
  jsr display_hex
  lda X2
  jsr display_hex
  lda X3
  jsr display_hex

wait:
  bra wait


disable_write_protection:
  ; Disable the write protection completely
  lda #$aa
  sta $8000 + $5555

  lda #$55
  sta $8000 + $2aaa

  lda #$80
  sta $8000 + $5555

  lda #$aa
  sta $8000 + $5555

  lda #$55
  sta $8000 + $2aaa

  lda #$20
  sta $8000 + $5555

  rts 
