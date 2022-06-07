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

  jsr test_lower_banks           ; 1
  jsr test_upper_banks           ; 2
  jsr test_fixed_upper_ram       ; 3
  jsr test_lower_bank_with_upper ; 4
  jsr test_access_eeprom         ; 5

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor

  jsr test_all                   ; 6
 
  lda tests_failed
  bne .failed

  jsr display_string_immediate
  .asciiz " OK"
  stp

.failed:
  jsr display_string_immediate
  .asciiz " F!"
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

  ldx #%10000
  lda #%00001
  jsr switch_to_space
  stx TEST_UPPER_VALUE

  ldx #%10001
.set_value_in_bank:
  txa
  jsr switch_to_space
  stx TEST_UPPER_VALUE
  inx
  cpx #%11000
  bne .set_value_in_bank

  ldx #%10000
  lda #%00001
  jsr switch_to_space
  cpx TEST_UPPER_VALUE
  bne .failed

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

  ldx #%10000
  lda #%00010
  jsr switch_to_space
  cpx TEST_UPPER_VALUE
  bne .failed

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


test_access_eeprom:
  lda #'5'
  jsr display_character

  stz $a000
  stz $a000 + 3

  lda #%10000
  jsr test_access_eeprom_2

  lda #%11000
  jsr test_access_eeprom_2

  rts


test_access_eeprom_2:
  jsr switch_to_space
  lda $a000
  cmp #$20 ; JSR
  bne .failed

  lda $a000 + 3
  cmp #$A9 ; LDA (immediate)
  bne .failed

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


test_all:
  lda #'6'
  jsr display_character

; Set Values

; 1..15      in lower bank 1..15   config 00001..01111 $2000
  ldx #1
  lda #%00001
.fill_lower_bank:
  jsr switch_to_space
  stx $2000
  inx
  inc
  cmp #%01111
  bne .fill_lower_bank

; 16         in lower fixed ram    config 00001        $6000
  ldx #16
  lda #%00001
  jsr switch_to_space
  stx $6000

; 17         in upper bank 1 L     config 00001        $a000
  ldx #17
  lda #%00001
  jsr switch_to_space
  stx $a000

; 18..24     in upper bank 2..8 L     config 10001..10111 $a000
  ldx #18
  lda #%10001
.fill_upper_bank_l:
  jsr switch_to_space
  stx $a000
  inx
  inc
  cmp #%10111
  bne .fill_upper_bank_l

; 25         in upper bank 1 H     config 00001        $e000
  ldx #25
  lda #%00001
  jsr switch_to_space
  stx $e000

; 26..32     in upper bank 2..8 H  config 10001..10111 $e000
  ldx #26
  lda #%10001
.fill_upper_bank_h:
  jsr switch_to_space
  stx $e000
  inx
  inc
  cmp #%10111
  bne .fill_upper_bank_h

; Check Values

; 1..15      in lower bank 1..15   config 00001..01111 $2000
  ldx #1
  lda #%00001
.check_lower_bank:
  jsr switch_to_space
  cpx $2000
  bne .check_lower_bank_failed
  inx
  inc
  cmp #%01111
  bne .check_lower_bank

  lda #'Y'
  jsr display_character
  bra .check_lower_bank_done

.check_lower_bank_failed:
  lda #'N'
  jsr display_character
  lda #1
  sta tests_failed

.check_lower_bank_done:

; 16         in lower fixed ram    config 00001        $6000
  ldx #16
  lda #%00001
  jsr switch_to_space
  cpx $6000
  bne .check_lower_fixed_ram_failed

  lda #'Y'
  jsr display_character
  bra .check_lower_fixed_ram_done

.check_lower_fixed_ram_failed:
  lda #'N'
  jsr display_character
  lda #1
  sta tests_failed

.check_lower_fixed_ram_done:

; 17         in upper bank 1 L     config 00001        $a000
  ldx #17
  lda #%00001
  jsr switch_to_space
  cpx $a000
  bne .check_upper_bank_1_l_failed
  lda #'Y'
  jsr display_character
  bra .check_upper_bank_1_l_done

.check_upper_bank_1_l_failed:
  lda #'N'
  jsr display_character
  lda #1
  sta tests_failed

.check_upper_bank_1_l_done:

; 18..24     in upper bank 2..8 L  config 10001..10111 $a000
  ldx #18
  lda #%10001
.check_upper_bank_l:
  jsr switch_to_space
  cpx $a000
  bne .check_upper_bank_l_failed
  inx
  inc
  cmp #%10111
  bne .check_upper_bank_l
  lda #'Y'
  jsr display_character
  bra .check_upper_bank_l_done

.check_upper_bank_l_failed:
  lda #'N'
  jsr display_character
  lda #1
  sta tests_failed

.check_upper_bank_l_done:

; 25         in upper bank 1 H     config 00001        $e000
  ldx #25
  lda #%00001
  jsr switch_to_space
  cpx $e000
  bne .check_upper_bank_1_h_failed
  lda #'Y'
  jsr display_character
  bra .check_upper_bank_1_h_done

.check_upper_bank_1_h_failed:
  lda #'N'
  jsr display_character
  lda #1
  sta tests_failed

.check_upper_bank_1_h_done:

; 26..32     in upper bank 2..8 H  config 10001..10111 $e000
  ldx #26
  lda #%10001
.check_upper_bank_h:
  jsr switch_to_space
  cpx $e000
  bne .check_upper_bank_h_failed
  inx
  inc
  cmp #%10111
  bne .check_upper_bank_h
  lda #'Y'
  jsr display_character
  bra .check_upper_bank_h_done

.check_upper_bank_h_failed:
  lda #'N'
  jsr display_character
  lda #1
  sta tests_failed

.check_upper_bank_h_done:

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
