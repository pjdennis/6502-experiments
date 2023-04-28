  .include base_config_v2.inc

;TODO ran into a bug that I can't recreate: scrolled past bottom; entered several
;lines of text; backspaced and it didn't stop at the cursor start position

INTERRUPT_ROUTINE        = $3f00

TAB_WIDTH                = 4
PROMPT_CHAR              = '>'

CP_M_DEST_P              = $00 ; 2 bytes
CP_M_SRC_P               = $02 ; 2 bytes
CP_M_LEN                 = $04 ; 2 bytes

CREATE_CHARACTER_PARAM   = $06 ; 2 bytes

SIMPLE_BUFFER_WRITE_PTR  = $08 ; 1 byte
SIMPLE_BUFFER_READ_PTR   = $09 ; 1 byte

DISPLAY_STRING_PARAM     = $0a ; 2 bytes
MULTIPLY_8X8_RESULT_LOW  = $0c ; 1 byte
MULTIPLY_8X8_TEMP        = $0d ; 1 byte
START_ROW                = $0e ; 1 byte
START_COL                = $0f ; 1 byte
LINE_PTR                 = $10 ; 2 bytes
COMMAND_FUNCTION_PTR     = $12 ; 2 bytes
TEMP_P                   = $14 ; 2 bytes

GD_ZERO_PAGE_BASE        = $16 ; 18 bytes

KB_ZERO_PAGE_BASE        = GD_ZERO_PAGE_STOP

SIMPLE_BUFFER            = $0200 ; 256 bytes
LINE_BUFFER              = $0300 ; GD_CHAR_ROWS * GD_CHAR_COLS = 400 bytes including terminating 0


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
  .include keyboard_driver.inc
  .include display_hex.inc
  .include multiply8x8.inc
  .include graphics_display.inc
  .include write_string_to_screen.inc


commands:
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

  jsr reset_and_enable_display_no_cursor
  lda #<start_message
  ldx #>start_message
  jsr display_string

  jsr keyboard_initialize

.loop:
  jsr gd_select
  jsr show_prompt
  lda #'_'
  jsr gd_show_character
  jsr gd_unselect

  jsr getline
  jsr execute_command

  bra .loop


start_message: .asciiz "Last key press:"

; On exit A contains the character read
getchar:
  phx
  phy
  lda (LINE_PTR)
  bne .buffer_has_data
; No data so read some
  jsr getline
  jsr initialize_line_ptr
  lda (LINE_PTR)
.buffer_has_data:
  inc LINE_PTR
  bne .done
  inc LINE_PTR + 1
.done
  ply
  plx
  rts


; Read and display translated characters from the keyboard
getline:
  lda GD_ROW
  sta START_ROW
  lda GD_COL
  sta START_COL
  jsr initialize_line_ptr
  ldx #0
.get_char_loop:
  cpx #0
  bne .not_off
  jsr gd_select
  lda #' '
  jsr gd_show_character
  jsr gd_unselect
.not_off:
  cpx #25
  bne .not_on
  jsr gd_select
  lda #'_'
  jsr gd_show_character
  jsr gd_unselect
.not_on:
  inx
  cpx #50
  bne .no_reset_count
  ldx #0
.no_reset_count:
  lda #1
  jsr delay_hundredths
  jsr keyboard_get_char
  bcs .get_char_loop
.get_char_loop_2:
  jsr callback_char_received
  bcs .done
  jsr keyboard_get_char
  bcc .get_char_loop_2
  jsr callback_no_more_chars
  bra .get_char_loop
.done
  rts


callback_char_received:
  jsr display_recieved_character
  jsr gd_select
  jsr handle_character_from_keyboard
  php ; preserve carry flag
  jsr gd_unselect
  plp
  rts


handle_character_from_keyboard:
  phx
  cmp #ASCII_BACKSPACE
  beq .backspace
  cmp #ASCII_LF
  beq .newline
; normal_char:
  tax
  lda START_ROW
  bne .store_char
  lda GD_ROW
  cmp #GD_CHAR_ROWS - 1
  bne .store_char
  lda GD_COL
  cmp #GD_CHAR_COLS - 1
  beq .return ; Have filled up the entire screen
.store_char:
  txa
  jsr line_buffer_add
  cmp #ASCII_TAB
  bne .show_char
; tab:
  lda #' '
.show_char:
  jsr gd_show_character
  lda GD_COL
  cmp #GD_CHAR_COLS - 1
  bne .not_last_char
  lda GD_ROW
  cmp #GD_CHAR_ROWS - 1
  bne .not_last_char
  jsr do_scroll
  bra .done
.not_last_char:
  jsr gd_next_character
  bra .done
.backspace:
  lda GD_ROW
  cmp START_ROW
  bne .not_first_char
  lda GD_COL
  cmp START_COL
  beq .return
.not_first_char:
  jsr line_buffer_delete
  lda #' '
  jsr gd_show_character
  lda GD_COL
  beq .previous_line
  dec
  sta GD_COL
  bra .done
.previous_line:
  dec GD_ROW
  lda #GD_CHAR_COLS - 1
  sta GD_COL
  bra .done
.newline:
  lda #' '
  jsr gd_show_character
  lda GD_ROW
  cmp #GD_CHAR_ROWS - 1
  bne .not_last_line
  jsr do_scroll
  bra .line_read
.not_last_line:  
  jsr gd_next_line
.line_read:
  lda #ASCII_LF
  jsr line_buffer_add
  lda #0
  jsr line_buffer_add
  sec
  bra .return2
.done:
  lda #'_'
  jsr gd_show_character
.return
  clc
.return2
  plx
  rts


execute_command:
  ; remove the newline from the command buffer
  jsr line_buffer_delete ; terminating 0
  jsr line_buffer_delete ; newline
  lda #0
  jsr line_buffer_add

  jsr find_command
  bcc .not_found
  jsr initialize_line_ptr
  stz LINE_BUFFER
  jsr jump_to_command_function
  bra .done

.not_found:
  jsr gd_select

  lda #<.unknown_command_string
  ldx #>.unknown_command_string
  jsr write_string_to_screen

  jsr show_line_buffer

  lda #ASCII_LF
  jsr write_character_to_screen

  jsr gd_unselect

.done:
  rts

.unknown_command_string: .asciiz "Unknown command: "


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

  jsr getline

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
  jsr getchar
  cmp #ASCII_LF
  beq .done
; show in hex
  jsr gd_select
  jsr convert_to_hex
  jsr write_character_to_screen
  txa
  jsr write_character_to_screen
  jsr gd_unselect
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


show_prompt:
  lda GD_COL
  beq .at_start_of_line
  lda GD_ROW
  cmp #GD_CHAR_ROWS - 1
  bne .not_last_line
  jsr do_scroll
  bra .prompt
.not_last_line
  jsr gd_next_line
.prompt
  stz GD_COL
.at_start_of_line:
  lda #PROMPT_CHAR
  jsr gd_show_character
  jsr gd_next_character
  rts


; On entry A contains the character to write
; On exit X, Y are preserved
;         A is not preserved
write_character_to_screen:
  cmp #ASCII_TAB
  beq .tab
  cmp #ASCII_LF
  beq .newline
  jsr gd_show_character
  lda GD_COL
  cmp #GD_CHAR_COLS - 1
  bne .not_last_char
  lda GD_ROW
  cmp #GD_CHAR_ROWS - 1
  bne .not_last_char
  jsr do_scroll
  bra .done
.not_last_char:
  jsr gd_next_character
  bra .done
.tab:
  jsr do_tab
  bra .done
.newline:
  lda GD_ROW
  cmp #GD_CHAR_ROWS - 1
  bne .not_last_line
  jsr do_scroll
  bra .done
.not_last_line:  
  jsr gd_next_line
.done:
  rts


; On exit X, Y are preserved
;         A is not preserved
do_tab:
  lda #' '
  jsr gd_show_character
  lda #TAB_WIDTH
.loop:
  cmp #GD_CHAR_COLS
  bcs .next_line
  cmp GD_COL
  beq .over1
  bcs .move_cursor ; A > GD_COL
.over1
  clc
  adc #TAB_WIDTH
  bra .loop
.next_line
  lda GD_ROW
  cmp #GD_CHAR_ROWS - 1
  bne .not_last_line
  jmp do_scroll ; tail call
.not_last_line:
  jmp gd_next_line ; tail call
.move_cursor:
  sta GD_COL
  rts

; Scroll up by 1 line
; On exit X, Y are preserved
;         A is not preserved
do_scroll:
  phx
  phy

  stz GD_ROW
  jsr gd_clear_line
  lda #1
  jsr gd_scroll_up
  lda #GD_CHAR_ROWS - 1
  sta GD_ROW
  stz GD_COL

  dec START_ROW

  ply
  plx
  rts


; On entry A = character recieved
; On exit A, X, Y are preserved
display_recieved_character:
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


callback_no_more_chars:
  rts


callback_key_left:
  rts


callback_key_right:
  rts


callback_key_esc:
  rts


callback_key_f1:
  pha
  phx
  phy

  jsr gd_select

  ldy #0
.loop:
  lda .f1_text, Y
  beq .done
  jsr handle_character_from_keyboard
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
  lda #<LINE_BUFFER
  ldx #>LINE_BUFFER
  jsr write_string_to_screen
  rts


initialize_line_ptr:
  lda #<LINE_BUFFER
  sta LINE_PTR
  lda #>LINE_BUFFER
  sta LINE_PTR + 1
  rts


line_buffer_add:
  sta (LINE_PTR)
  inc LINE_PTR
  bne .done
  inc LINE_PTR + 1
.done:
  rts


line_buffer_delete:
  pha
  lda LINE_PTR
  bne .high_byte_good
  dec LINE_PTR + 1
.high_byte_good:
  dec LINE_PTR
  pla
  rts

; On entry LINE_BUFFER contains the potential command
; On exit COMMAND_FUNCTION_PTR contains the address of the command function if found
;         C is set if command found or clear if not found
;         A, X, Y are preserved
; Uses LINE_PTR
find_command:
  pha
  phy

  ; TEMP_P <- address of 'commands' table
  lda #<commands
  sta TEMP_P
  lda #>commands
  sta TEMP_P + 1

  .command_loop:
  lda (TEMP_P)
  beq .not_found

  ; At start of line; comare with command buffer
  jsr initialize_line_ptr
  ldy #0
  .char_loop:
  lda (TEMP_P),Y
  cmp (LINE_PTR),Y
  bne .next
  lda (TEMP_P),Y
  beq .found
  iny
  bra .char_loop

; Found. Read address
.found:
  iny
  lda (TEMP_P),Y
  sta COMMAND_FUNCTION_PTR
  iny
  lda (TEMP_P),Y
  sta COMMAND_FUNCTION_PTR + 1
  sec
  bra .done

.next:
  lda (TEMP_P),Y
  beq .skip_to_next
  iny
  bra .next

.skip_to_next: ; skip past the trailing 0 and 2 bytes of address
  clc
  tya
  adc #3

  ; carry assumed clear
  adc TEMP_P
  sta TEMP_P
  lda #0
  adc TEMP_P + 1
  sta TEMP_P + 1

  bra .command_loop

.not_found:
  clc
  ; Fall through

.done:
  ply
  pla
  rts
