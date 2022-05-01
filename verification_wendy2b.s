  .include base_config_wendy2c.inc

D_S_I_P                = $00 ; 2 bytes
TEMP                   = $02
TEST_VALUE             = $03
TEST_UPPER_VALUE       = $efff
TEST_FIXED_UPPER_VALUE = $f800

  .org $4000
  jmp program_entry

  ; Place code for delay_routines at start of page to ensure no page boundary crossings
  ; during timing loops
  .include delay_routines.inc

  .include display_routines_4bit.inc
  .include display_hex.inc
  .include display_string_immediate.inc 

switch_to_space_return: .word 0
switch_to_space_space: .byte 0
tests_failed: .byte 0

program_entry:
  jsr clear_display

  stz tests_failed

  jsr test_lower_banks
  jsr test_upper_banks
  jsr test_fixed_upper_ram
  jsr test_lower_bank_with_upper

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
 
  lda tests_failed
  bne .failed

  jsr display_string_immediate
  .asciiz "Succeeded."
  stp

.failed:
  jsr display_string_immediate
  .asciiz "Failed!"
  stp


test_lower_banks:
  lda #'1'
  jsr display_character

  ldx #1
.set_value_in_bank:
  txa
  jsr switch_to_space
  stx TEST_VALUE
  inx
  cpx #16
  bne .set_value_in_bank

  ldx #1
.check_value_in_bank:
  txa
  jsr switch_to_space
  cpx TEST_VALUE
  bne .failed
  inx

  cpx #16
  bne .check_value_in_bank

  lda #'Y'
  jsr display_character

  bra .done

.failed:
  lda #'N'
  jsr display_character
  lda #1
  sta tests_failed

.done:
  lda #1
  jsr switch_to_space
  rts


test_upper_banks:
  lda #'2'
  jsr display_character

  ldx #%10001
.set_value_in_bank:
  txa
  jsr switch_to_space
  stx TEST_UPPER_VALUE
  inx
  cpx #%11000
  bne .set_value_in_bank

  ldx #%10001
.check_value_in_bank:
  txa
  jsr switch_to_space
  cpx TEST_UPPER_VALUE
  bne .failed
  inx
  cpx #%11000
  bne .check_value_in_bank

  lda #'Y'
  jsr display_character

  ldx #%10001
  ldy #%11001
.check_value_in_bank_copy:
  tya
  jsr switch_to_space
  cpx TEST_UPPER_VALUE
  bne .failed
  inx
  iny
  cpx #%11000
  bne .check_value_in_bank_copy

  lda #'Y'
  jsr display_character

  bra .done

.failed:
  lda #'N'
  jsr display_character
  lda #1
  sta tests_failed

.done:
  lda #1
  jsr switch_to_space
  rts


test_fixed_upper_ram:
  lda #'3'
  jsr display_character

  ldx #%10001
.set_value_in_bank:
  txa
  jsr switch_to_space
  stz TEST_FIXED_UPPER_VALUE
  inx
  cpx #%11000
  bne .set_value_in_bank

  lda #%10000
  jsr switch_to_space
  lda #1
  sta TEST_FIXED_UPPER_VALUE

  ldx #%10000
.check_value_in_bank:
  txa
  jsr switch_to_space
  lda #1
  cmp TEST_FIXED_UPPER_VALUE
  bne .failed
  inx
  cpx #%11000
  bne .check_value_in_bank

  lda #'Y'
  jsr display_character

  ldx #%11000
.check_value_in_bank_copy:
  txa
  jsr switch_to_space
  lda #1
  cmp TEST_FIXED_UPPER_VALUE
  bne .failed
  inx
  cpx #%100000
  bne .check_value_in_bank_copy

  lda #'Y'
  jsr display_character

  bra .done

.failed:
  lda #'N'
  jsr display_character
  lda #1
  sta tests_failed

.done:
  lda #1
  jsr switch_to_space
  rts


test_lower_bank_with_upper:
  lda #'4'
  jsr display_character

  lda #00001
  jsr switch_to_space
  lda #1
  sta TEST_VALUE

  lda #00010
  jsr switch_to_space
  lda #2
  sta TEST_VALUE

  ldx #3
.set_value_in_bank:
  txa
  jsr switch_to_space
  stz TEST_VALUE
  inx
  cpx #16
  bne .set_value_in_bank
 
  ldx #%10001
.check_value_in_bank:
  txa
  jsr switch_to_space
  lda #1
  cmp TEST_VALUE
  bne .failed
  inx
  cpx #%11000
  bne .check_value_in_bank

  lda #'Y'
  jsr display_character

  ldx #%11001
.check_value_in_bank_copy:
  txa
  jsr switch_to_space
  lda #2
  cmp TEST_VALUE
  bne .failed
  inx
  cpx #%100000
  bne .check_value_in_bank_copy

  lda #'Y'
  jsr display_character

  bra .done

.failed:
  lda #'N'
  jsr display_character
  lda #1
  sta tests_failed

.done:
  lda #1
  jsr switch_to_space
  rts


; On entry A contains the space to switch to
; on exit A, X, Y are preserved
switch_to_space:
  sta switch_to_space_space
  pla
  sta switch_to_space_return
  pla
  sta switch_to_space_return + 1

  lda switch_to_space_space

  and #BANK_MASK
  sta TEMP
  lda BANK_PORT
  and #~BANK_MASK
  ora TEMP
  sta BANK_PORT

  lda switch_to_space_return + 1
  pha
  lda switch_to_space_return
  pha
  lda switch_to_space_space
  rts

