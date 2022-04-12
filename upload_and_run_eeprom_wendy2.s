ORIGIN               = $8000
UPLOAD_TO            = $4000

BPS_HUNDREDS         = 1152 ; 115200 bps

SHOULD_SWITCH_TO_RAM = 1;

  .include base_config_wendy2.inc
  .include upload_and_run.inc
  .include initialize_machine_wendy2.inc
  .include display_routines_4bit.inc
  .include copy_memory.inc

ready_message: asciiz 'Ready.'

IRQ_VECTOR_ADDRESS    = $fffe
FIXED_RAM             = $4000
FIXED_RAM_OFFSET      = ORIGIN - FIXED_RAM
PROGRAM_LENGTH        = program_end - ORIGIN

switch_to_ram:
  ; copy PROGRAM_LENGTH bytes from program_start to FIXED_RAM
  lda #<FIXED_RAM
  sta CP_M_DEST_P
  lda #>FIXED_RAM
  sta CP_M_DEST_P + 1
  lda #<ORIGIN
  sta CP_M_SRC_P
  lda #>ORIGIN
  sta CP_M_SRC_P + 1
  lda #<PROGRAM_LENGTH
  sta CP_M_LEN
  lda #>PROGRAM_LENGTH
  sta CP_M_LEN + 1
  jsr copy_memory

  ; jmp to switch_to_ram_part_2 within FIXED_RAM (switch_to_ram_part_2 - FIXED_RAM_OFFSET)
  jmp switch_to_ram_part_2 - FIXED_RAM_OFFSET


switch_to_ram_part_2:
  ; switch out ROM for RAM
  lda #BANK_MASK
  trb BANK_PORT
  lda #BANK_START
  tsb BANK_PORT

  ldx #$ff                                 ; Initialize stack
  txs

  ; copy PROGRAM_LENGTH bytes from FIXED_RAM to program_start
  lda #<ORIGIN
  sta CP_M_DEST_P
  lda #>ORIGIN
  sta CP_M_DEST_P + 1
  lda #<FIXED_RAM
  sta CP_M_SRC_P
  lda #>FIXED_RAM
  sta CP_M_SRC_P + 1
  lda #<PROGRAM_LENGTH
  sta CP_M_LEN
  lda #>PROGRAM_LENGTH
  sta CP_M_LEN + 1
  jsr copy_memory - FIXED_RAM_OFFSET

  ; Store the interrupt vector
  lda #<INTERRUPT_ROUTINE
  sta IRQ_VECTOR_ADDRESS
  lda #>INTERRUPT_ROUTINE
  sta IRQ_VECTOR_ADDRESS + 1

  ; return to the calling code
  jmp switch_to_ram_continue


program_end:

; Vectors
  .org $fffc
  .word ORIGIN
  .word $0000
