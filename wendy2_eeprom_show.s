D_S_I_P       = $00   ; 2 bytes

TEST_LOCATION = $fe00

  .org $4000
  jmp program_entry

  .include base_config_wendy2.inc
  .include display_update_routines.inc
  .include display_string_immediate.inc
  .include display_hex.inc

program_entry:
; Program code goes here

  lda #BANK_MASK
  trb BANK_PORT

  jsr display_string_immediate
  .asciiz "Value: "
  lda TEST_LOCATION
  jsr display_hex

  stp
