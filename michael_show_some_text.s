  .include base_config_v2.inc

INTERRUPT_ROUTINE        = $3f00

TAB_WIDTH                = 4

CP_M_DEST_P              = $00 ; 2 bytes
CP_M_SRC_P               = $02 ; 2 bytes
CP_M_LEN                 = $04 ; 2 bytes

CREATE_CHARACTER_PARAM   = $06 ; 2 bytes

SIMPLE_BUFFER_WRITE_PTR  = $08 ; 1 byte
SIMPLE_BUFFER_READ_PTR   = $09 ; 1 byte

DISPLAY_STRING_PARAM     = $0A ; 2 bytes
TEXT_PTR                 = $0C ; 2 bytes
TEXT_PTR_NEXT            = $0E ; 2 bytes
SCROLL_OFFSET            = $10 ; 2 bytes
LINE_CHARS_REMAINING     = $12 ; 1 byte
MULTIPLY_8X8_RESULT_LOW  = $13 ; 1 byte
MULTIPLY_8X8_TEMP        = $14 ; 1 byte

GD_ZERO_PAGE_BASE        = $15 ; 18 bytes

KB_ZERO_PAGE_BASE        = GD_ZERO_PAGE_STOP

SIMPLE_BUFFER            = $0200 ; 256 bytes

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

program_start:
  ; Initialize stack
  ldx #$ff
  txs

  jsr gd_configure
  jsr gd_reset
  jsr gd_select
  jsr gd_initialize
  lda #ILI9341_MADCTL
  jsr gd_send_command
  lda #%10101000    ; original $48
  jsr gd_send_data
  jsr gd_clear_screen
  jsr gd_unselect

  stz GD_ROW
  stz GD_COL

  jsr gd_select

  jsr show_some_text

  jsr gd_unselect

  stp


callback_no_more_chars:
  rts


callback_key_left:
  rts


callback_key_right:
  rts


callback_key_esc:
  rts


callback_key_f1:
  rts


show_some_text:
  lda #<message_text
  sta TEXT_PTR
  lda #>message_text
  sta TEXT_PTR + 1
  lda #GD_CHAR_COLS
  sta LINE_CHARS_REMAINING
.show_spaces_loop:
  lda LINE_CHARS_REMAINING
  beq .skip_remaining_spaces
  lda (TEXT_PTR)
  beq .done
  cmp #' '
  bne .show_text
  jsr gd_show_character
  jsr gd_next_character
  dec LINE_CHARS_REMAINING
  inc TEXT_PTR
  bne .show_spaces_loop
  inc TEXT_PTR + 1
  bra .show_spaces_loop
.show_text:
  lda (TEXT_PTR)
  beq .done
; look for end of word
  ldy #1
.word_search_loop:
  lda (TEXT_PTR),Y
  beq .found_word_end
  cmp #' '
  beq .found_word_end
  iny
  cpy #GD_CHAR_COLS
  bne .word_search_loop
.found_word_end:
; will word fit on line?
  cpy LINE_CHARS_REMAINING
  bcc .word_fits
  beq .word_fits
; word does not fit
.finish_line_loop:
  lda #' '
  jsr gd_show_character
  jsr gd_next_character
  dec LINE_CHARS_REMAINING
  bne .finish_line_loop
  lda #GD_CHAR_COLS
  sta LINE_CHARS_REMAINING
.word_fits:
.show_word_loop:
  lda (TEXT_PTR)
  jsr gd_show_character
  jsr gd_next_character
  dec LINE_CHARS_REMAINING
  inc TEXT_PTR
  bne .over
  inc TEXT_PTR + 1
.over:
  dey
  bne .show_word_loop
  bra .show_spaces_loop
.skip_remaining_spaces:
  lda #GD_CHAR_COLS
  sta LINE_CHARS_REMAINING
.skip_spaces_loop:
  lda (TEXT_PTR)
  beq .done
  cmp #' '
  bne .show_text
  inc TEXT_PTR
  bne .skip_spaces_loop
  inc TEXT_PTR + 1
  bra .skip_spaces_loop
.done:
  lda LINE_CHARS_REMAINING
  cmp #GD_CHAR_COLS
  beq .exit
.finish_last_line_loop:
  lda #' '
  jsr gd_show_character
  jsr gd_next_character
  dec LINE_CHARS_REMAINING
  bne .finish_last_line_loop
.exit:
  rts

message_text: .asciiz "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."

;message_text: .asciiz "  a 1234567890123456789 b 12345678901234567890 c 123456789012345678901 d e the quick brown fox. 123456789"
