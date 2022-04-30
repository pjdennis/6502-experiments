ORIGIN               = $4000
UPLOAD_TO            = $5000

BPS_HUNDREDS         = 2304 ; 230400 bps

SHOULD_SWITCH_TO_RAM = 1;

  .include base_config_wendy2b.inc
  .include upload_and_run.inc
  .include initialize_machine_wendy2b.inc
  .include display_routines_4bit.inc

ready_message: asciiz 'Ready (RAM).'

IRQ_VECTOR_ADDRESS    = $fffe

switch_to_ram:
  ; switch out ROM for RAM
  lda #BANK_MASK
  trb BANK_PORT
  lda #BANK_START
  tsb BANK_PORT

  ; Store the interrupt vector
  lda #<INTERRUPT_ROUTINE
  sta IRQ_VECTOR_ADDRESS
  lda #>INTERRUPT_ROUTINE
  sta IRQ_VECTOR_ADDRESS + 1

  ; return to the calling code
  jmp switch_to_ram_continue
