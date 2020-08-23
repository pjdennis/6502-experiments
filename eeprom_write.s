  .include base_config_v1.inc

D_S_I_P       = $00   ; 2 bytes

TEST_LOCATION = $fe00

  .org $2000
  jmp program_entry

  .include display_string_immediate.inc
  .include display_hex.inc

program_entry:
; Program code goes here

  jsr display_string_immediate
  .asciiz "Before: "
  ldx TEST_LOCATION
  txa
  jsr display_hex

  inx

  ; TODO update EEPROM data
  lda #$aa
  sta $8000 + $5555

  lda #$55
  sta $8000 + $2aaa

  lda #$a0
  sta $8000 + $5555

  txa
  sta TEST_LOCATION

wait_for_completion_loop:
  cmp TEST_LOCATION
  bne wait_for_completion_loop

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  jsr display_string_immediate
  .asciiz " After: "
  lda TEST_LOCATION
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
