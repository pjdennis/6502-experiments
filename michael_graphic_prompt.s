  .include base_config_v2.inc

;TODO ran into a bug that I can't recreate: scrolled past bottom; entered several
;lines of text; backspaced and it didn't stop at the cursor start position

INTERRUPT_ROUTINE        = $3f00


; Zero page allocations
CP_M_DEST_P              = $00 ; 2 bytes
CP_M_SRC_P               = $02 ; 2 bytes
CP_M_LEN                 = $04 ; 2 bytes

CREATE_CHARACTER_PARAM   = $06 ; 2 bytes

SIMPLE_BUFFER_WRITE_PTR  = $08 ; 1 byte
SIMPLE_BUFFER_READ_PTR   = $09 ; 1 byte

DISPLAY_STRING_PARAM     = $0a ; 2 bytes
MULTIPLY_8X8_RESULT_LOW  = $0c ; 1 byte
MULTIPLY_8X8_TEMP        = $0d ; 1 byte

GD_ZERO_PAGE_BASE        = $0e

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
EXTEND_CHARACTER_SET = 1
  .include display_routines.inc
  .include display_string.inc
  .include simple_buffer.inc
  .include copy_memory.inc
  .include key_codes.inc
  .include keyboard_typematic.inc
KB_BUFFER_INITIALIZE = simple_buffer_initialize
KB_BUFFER_WRITE      = simple_buffer_write
KB_BUFFER_READ       = simple_buffer_read
callback_key_f1      = handle_f1
  .include keyboard_driver.inc
  .include display_hex.inc
  .include multiply8x8.inc
  .include graphics_display.inc
gc_callback_char_received = sk_show_char_info
  .include graphics_console.inc
  .include write_string_to_screen.inc
  .include command_table.inc
  .include console_repl.inc
  .include show_keys_on_screen.inc


CT_COMMANDS:
  .asciiz "echo"
                      .word command_echo
  .asciiz "hello"
                      .word command_hello
  .asciiz "clear"
                      .word command_clear
  .asciiz "Angel"
                      .word command_angel
  .asciiz "angel"
                      .word command_angel
  .asciiz "getchar"
                      .word command_getchar
  .byte 0

 
program_start:
  ; Initialize stack
  ldx #$ff
  txs

  jsr gd_prepare_vertical
  jsr gc_initialize
  jsr keyboard_initialize
  jsr reset_and_enable_display_no_cursor
  jsr sk_init

  jsr cr_repl

  stp


command_hello:
  jsr gd_select

  lda #<.message_string
  ldx #>.message_string
  jsr write_string_to_screen

  jsr gd_unselect
  rts

.message_string: .asciiz "Hello, world!\n"


command_angel:
  jsr gd_select

  lda #<.message_string
  ldx #>.message_string
  jsr write_string_to_screen

  jsr gd_unselect
  rts

.message_string: .asciiz "Phil :==D Angel :)\n"


command_echo:
  jsr gd_select

  lda #<.command_string
  ldx #>.command_string
  jsr write_string_to_screen

  jsr gd_unselect

  jsr gc_getline

  jsr gd_select

  lda #<.message_string
  ldx #>.message_string
  jsr write_string_to_screen

  jsr gc_show_line_buffer

  jsr gd_unselect

  rts

.command_string: .asciiz "Enter text: "
.message_string: .asciiz "You entered: "


command_getchar:
  jsr gd_select

  lda #<.command_string
  ldx #>.command_string
  jsr write_string_to_screen

  jsr gd_unselect

.loop:
  jsr gc_getchar
  cmp #ASCII_LF
  beq .done
; show in hex
  jsr convert_to_hex
  jsr gc_putchar
  txa
  jsr gc_putchar
  bra .loop
.done:
  rts

.command_string: .asciiz "Enter text: "


command_clear:
  jsr gd_select
  jsr gd_clear_screen
  jsr gd_unselect
  stz GD_ROW
  rts


handle_f1:
  pha
  phx
  phy

  jsr gd_select

  ldy #0
.loop:
  lda .f1_text, Y
  beq .done
  jsr gc_handle_char_from_keyboard
  iny
  bra .loop
.done:
  jsr gd_unselect

  ply
  plx
  pla
  rts
.f1_text: .asciiz "The quick brown fox jumps over the lazy dog. "
