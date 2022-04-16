DISPLAY_STRING_PARAM = $00   ; 2 bytes
CP_M_DEST_P          = $02   ; 2 bytes
CP_M_SRC_P           = $04   ; 2 bytes
CP_M_LEN             = $06   ; 2 bytes

ORIGIN               = $8000
FIXED_RAM            = $4000
FIXED_RAM_OFFSET     = ORIGIN - FIXED_RAM
PROGRAM_LENGTH       = program_end - ORIGIN


  .include base_config_wendy2.inc

  .org ORIGIN
  jmp program_start

  .include delay_routines.inc
  .include display_string.inc
  .include display_routines_4bit.inc
  .include copy_memory.inc

message_line_1: asciiz "Hello."
message_line_2: asciiz "1Abc 123456xyz"

program_start:
  ldx #$ff ; Initialize stack
  txs

  lda #0   ; Initialize status flags
  pha
  plp


  ; Initialize hardware

  ; Memory Banking
  lda #BANK_MASK
  trb BANK_PORT
  tsb BANK_PORT + DDR_OFFSET

  ; Display
  lda #DISPLAY_BITS_MASK
  trb DISPLAY_DATA_PORT
  tsb DISPLAY_DATA_PORT + DDR_OFFSET

  lda #E
  trb DISPLAY_ENABLE_PORT
  tsb DISPLAY_ENABLE_PORT + DDR_OFFSET

  jmp switch_to_ram
switch_to_ram_continue:


  jsr reset_and_enable_display_no_cursor

  lda #<message_line_1
  ldx #>message_line_1
  jsr display_string

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  lda #<message_line_2
  ldx #>message_line_2
  jsr display_string

  stp


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

  ; return to the calling code
  jmp switch_to_ram_continue


program_end:


  .org $fffc
  .word ORIGIN
  .word $0000
