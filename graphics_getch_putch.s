  .include base_config_v2.inc

INTERRUPT_ROUTINE        = $3f00


; Zero page allocations
ZERO_PAGE_BASE           = $00

CP_M_DEST_P              = ZERO_PAGE_BASE + $00 ; 2 bytes
CP_M_SRC_P               = ZERO_PAGE_BASE + $02 ; 2 bytes
CP_M_LEN                 = ZERO_PAGE_BASE + $04 ; 2 bytes

SIMPLE_BUFFER_WRITE_PTR  = ZERO_PAGE_BASE + $06 ; 1 byte
SIMPLE_BUFFER_READ_PTR   = ZERO_PAGE_BASE + $07 ; 1 byte

DISPLAY_STRING_PARAM     = ZERO_PAGE_BASE + $08 ; 2 bytes
MULTIPLY_8X8_RESULT_LOW  = ZERO_PAGE_BASE + $0a ; 1 byte
MULTIPLY_8X8_TEMP        = ZERO_PAGE_BASE + $0b ; 1 byte

GD_ZERO_PAGE_BASE        = ZERO_PAGE_BASE + $0c

KB_ZERO_PAGE_BASE        = GD_ZERO_PAGE_STOP
GC_ZERO_PAGE_BASE        = KB_ZERO_PAGE_STOP
CT_ZERO_PAGE_BASE        = GC_ZERO_PAGE_STOP


; Other memory allocations
SIMPLE_BUFFER            = $0200 ; 256 bytes
GC_LINE_BUFFER           = $0300 ; GD_CHAR_ROWS * GD_CHAR_COLS = 400 bytes including terminating 0


  .org $2000                     ; Loader loads programs to this address
  jmp initialize_machine         ; Initialize hardware and then jump to program_start

  ; The initialize_machine routine in this include will set up hardware registers and then
  ; jump to program_start. We do not call a subroutine because for some machine designs the
  ; stack is not usable until after the hardware registers have been initialized
  .include delay_routines.inc
  .include initialize_machine_v2.inc

  .include simple_buffer.inc
  .include copy_memory.inc
  .include key_codes.inc
  .include keyboard_typematic.inc
KB_BUFFER_INITIALIZE    = simple_buffer_initialize
KB_BUFFER_WRITE         = simple_buffer_write
KB_BUFFER_READ          = simple_buffer_read
;KB_NO_INTERRUPT_HANDLER = 1
  .include keyboard_driver.inc
  .include multiply8x8.inc
  .include graphics_display.inc
  .include graphics_console.inc
  .include write_string_to_screen.inc
  .include command_table.inc
  .include console_repl.inc


CT_COMMANDS:
  .asciiz "exit"
                      .word 0
  .byte 0

 
program_start:
  ; Initialize stack
  ldx #$ff
  txs

  jsr gd_prepare_vertical
  jsr gc_initialize
  jsr keyboard_initialize

  jsr cr_repl

  lda #<.exit_message
  ldx #>.exit_message
  jsr gc_putstring

  stp

.exit_message: .asciiz "Exited.\n"
