  .include base_config_v1.inc

  .org $2000

program_entry:
  lda #ACR_SR_OUT_CK
  sta ACR
  stz SR
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  stz ACR
  ldx #0
  jmp ($fffc,X)
