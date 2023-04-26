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

LINE_LENGTHS             = $0300 ; GD_CHAR_COLS bytes 

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

  jsr gd_prepare_vertical

  jsr gd_select
  lda #'_'
  jsr gd_show_character
  jsr gd_unselect

  jsr reset_and_enable_display_no_cursor
  lda #<start_message
  ldx #>start_message
  jsr display_string

  jsr keyboard_initialize

  ; Read and display translated characters from the keyboard

  ldx #0
get_char_loop:
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
  bcs get_char_loop
get_char_loop_2:
  jsr callback_char_received
  jsr keyboard_get_char
  bcc get_char_loop_2
  jsr callback_no_more_chars
  bra get_char_loop


start_message: .asciiz "Last key press:"


callback_char_received:
  phx
  phy
  jsr display_recieved_character
  jsr gd_select
  cmp #$08
  beq .backspace
  cmp #$09
  beq .tab
  cmp #$0a
  beq .newline
  jsr gd_show_character
  lda GD_ROW
  cmp #GD_CHAR_ROWS - 1
  bne .not_last_char
  lda GD_COL
  cmp #GD_CHAR_COLS - 1
  bne .not_last_char
  jsr do_scroll
  bra .done
.not_last_char:
  jsr gd_next_character
  bra .done
.backspace:
  lda GD_ROW
  bne .not_first_char
  lda GD_COL
  beq .return
.not_first_char:
  lda #' '
  jsr gd_show_character
  jsr gd_previous_character
  bra .done
.tab:
  jsr do_tab
  bra .done
.newline:
  lda #' '
  jsr gd_show_character
  lda GD_ROW
  cmp #GD_CHAR_ROWS - 1
  bne .not_last_line
  jsr do_scroll
  bra .done
.not_last_line:  
  jsr gd_next_line
.done:
  lda #'_'
  jsr gd_show_character
.return
  jsr gd_unselect
  ply
  plx
  rts


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


do_scroll:
  stz GD_ROW
  jsr gd_clear_line
  lda #1
  jsr gd_scroll_up
  lda #GD_CHAR_ROWS - 1
  sta GD_ROW
  stz GD_COL
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
  ldy #0
.loop:
  lda .f1_text, Y
  beq .done
  jsr callback_char_received
  iny
  bra .loop
.done:
  rts

.f1_text: .asciiz "The quick brown fox jumps over the lazy dog. "
