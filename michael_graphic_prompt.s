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

COMMAND_FUNCTION_PTR     = $0e ; 2 bytes

GD_ZERO_PAGE_BASE        = $10

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
  .include graphics_console.inc
  .include write_string_to_screen.inc
  .include command_table.inc


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
  lda #<.start_message
  ldx #>.start_message
  jsr display_string

.loop:
  jsr gc_show_prompt
  jsr gc_getline
  jsr execute_command
  bra .loop

.start_message: .asciiz "Last key press:"


execute_command:
  ; remove the newline from the command buffer
  jsr gc_line_buffer_delete ; terminating 0
  jsr gc_line_buffer_delete ; newline
  lda #0
  jsr gc_line_buffer_add

  ; check for empty command line
  jsr check_line_blank
  bcs .done

  jsr ct_find_command
  bcc .not_found
  jsr gc_initialize_line_ptr
  stz GC_LINE_BUFFER
  jsr jump_to_command_function
  bra .done

.not_found:
  jsr gd_select

  lda #<.unknown_command_string
  ldx #>.unknown_command_string
  jsr write_string_to_screen

  jsr show_line_buffer

  lda #ASCII_LF
  jsr gc_write_char_to_screen

  jsr gd_unselect

.done:
  rts

.unknown_command_string: .asciiz "Unknown command: "


; On exit C set if line is blank, clear otherwise
;         X, Y are preserved
;         A is not preserved
check_line_blank:
  jsr gc_initialize_line_ptr
.loop:
  lda (GC_LINE_PTR)
  beq .is_blank
  cmp #' '
  beq .blank_char
  cmp #ASCII_TAB
  beq .blank_char
; non-blank character
  clc
  bra .done
.blank_char
  inc GC_LINE_PTR
  bne .loop
  inc GC_LINE_PTR + 1
  bra .loop
.is_blank
  sec
.done
  rts


jump_to_command_function:
  jmp (COMMAND_FUNCTION_PTR)


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

  jsr show_line_buffer

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


; On entry A = character recieved
; On exit A, X, Y are preserved
callback_char_recieved:
  phx
  tax
  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  txa
  jsr display_character
  lda #' '
  jsr display_character
  txa
  jsr display_hex
  txa
  plx
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


show_line_buffer:
  lda #<GC_LINE_BUFFER
  ldx #>GC_LINE_BUFFER
  jsr write_string_to_screen
  rts


; On entry GC_LINE_BUFFER contains the potential command
; On exit COMMAND_FUNCTION_PTR contains the address of the command function if found
;         C is set if command found or clear if not found
;         A, X, Y are preserved
; Uses GC_LINE_PTR
ct_find_command:
  pha
  phy

  ; CT_TABLE_PTR <- address of 'commands' table
  lda #<CT_COMMANDS
  sta CT_TABLE_PTR
  lda #>CT_COMMANDS
  sta CT_TABLE_PTR + 1

  .command_loop:
  lda (CT_TABLE_PTR)
  beq .not_found

  ; At start of line; comare with command buffer
  jsr gc_initialize_line_ptr
  ldy #0
  .char_loop:
  lda (CT_TABLE_PTR),Y
  cmp (GC_LINE_PTR),Y
  bne .next
  lda (CT_TABLE_PTR),Y
  beq .found
  iny
  bra .char_loop

; Found. Read address
.found:
  iny
  lda (CT_TABLE_PTR),Y
  sta COMMAND_FUNCTION_PTR
  iny
  lda (CT_TABLE_PTR),Y
  sta COMMAND_FUNCTION_PTR + 1
  sec
  bra .done

.next:
  lda (CT_TABLE_PTR),Y
  beq .skip_to_next
  iny
  bra .next

.skip_to_next: ; skip past the trailing 0 and 2 bytes of address
  clc
  tya
  adc #3

  ; carry assumed clear
  adc CT_TABLE_PTR
  sta CT_TABLE_PTR
  lda #0
  adc CT_TABLE_PTR + 1
  sta CT_TABLE_PTR + 1

  bra .command_loop

.not_found:
  clc
  ; Fall through

.done:
  ply
  pla
  rts
