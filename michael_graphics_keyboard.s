  .include base_config_v2.inc

INTERRUPT_ROUTINE        = $3f00

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
GD_ZERO_PAGE_BASE        = $13 ; 18 bytes

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
  .include graphics_display.inc

; Code sequence for the pause/break key
kb_seq_pause        .byte $e1, $14, $77, $e1, $f0, $14, $f0, $77, $00

; Mapping from PS/2 code set 3 lock keys to the bit mask used for tracking lock down/up and on/off
kb_lock_codes:      .byte KEY_CAPSLOCK,      KEY_SCROLLLOCK,      KEY_NUMLOCK,     $00
kb_lock_on_masks:   .byte KB_CAPS_LOCK_ON,   KB_SCROLL_LOCK_ON,   KB_NUM_LOCK_ON,  $00
kb_lock_down_masks: .byte KB_CAPS_LOCK_DOWN, KB_SCROLL_LOCK_DOWN, KB_NUM_LOCK_DOWN
kb_lock_to_led:     .byte KB_LED_CAPS_LOCK,  KB_LED_SCROLL_LOCK,  KB_LED_NUM_LOCK

; Mapping from PS/2 code set 3 modifier keys to the bit mask used for tracking modifier states
kb_modifier_codes:  .byte KEY_LEFTSHIFT,   KEY_RIGHTSHIFT,  KEY_LEFTCTRL,   KEY_RIGHTCTRL
                    .byte KEY_LEFTALT,     KEY_RIGHTALT,    KEY_LEFTMETA,   KEY_RIGHTMETA, $00
kb_modifier_masks:  .byte KB_MOD_L_SHIFT,  KB_MOD_R_SHIFT,  KB_MOD_L_CTRL,  KB_MOD_R_CTRL
                    .byte KB_MOD_L_ALT,    KB_MOD_R_ALT,    KB_MOD_L_GUI,   KB_MOD_R_GUI

; Mapping from the modifier state masks for left/right modifier keys to the mask used to
; indicate at least one of the keys is pressed
kb_modifier_from:   .byte (KB_MOD_L_SHIFT | KB_MOD_R_SHIFT), (KB_MOD_L_CTRL | KB_MOD_R_CTRL)
                    .byte (KB_MOD_L_ALT   | KB_MOD_R_ALT),   (KB_MOD_L_GUI  | KB_MOD_R_GUI), $00
kb_modifier_to      .byte KB_META_SHIFT,                     KB_META_CTRL
                    .byte KB_META_ALT,                       KB_META_GUI

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

;  jsr show_some_text

;  stz GD_ROW
;  jsr gd_clear_line
;  lda #1


;SCROLL_MAX = ILI9341_TFTHEIGHT - 16
;  lda #<SCROLL_MAX
;  sta SCROLL_OFFSET
;  lda #>SCROLL_MAX
;  sta SCROLL_OFFSET + 1
;.scroll_loop:
;; send command
;  lda #ILI9341_VSCRSADD
;  jsr gd_send_command
;  lda SCROLL_OFFSET + 1
;  jsr gd_send_data
;  lda SCROLL_OFFSET
;  jsr gd_send_data
;  lda #50
;  jsr delay_hundredths
;; check for end
;  lda SCROLL_OFFSET
;  bne .scroll_offset_ok
;  lda SCROLL_OFFSET + 1
;  bne .scroll_offset_ok
;  lda #<SCROLL_MAX
;  sta SCROLL_OFFSET
;  lda #>SCROLL_MAX
;  sta SCROLL_OFFSET + 1
;  bra .scroll_loop
;.scroll_offset_ok:
;; decrement offset
;  sec
;  lda SCROLL_OFFSET
;  sbc #16
;  sta SCROLL_OFFSET
;  lda SCROLL_OFFSET + 1
;  sbc #0
;  sta SCROLL_OFFSET + 1
;  bra .scroll_loop

;  lda #GD_CHAR_ROWS - 2
;  sta GD_ROW

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
  pha
  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  pla
  pha
  jsr display_character
  lda #' '
  jsr display_character
  pla
  pha
  jsr display_hex
  jsr gd_select
  pla
  cmp #0x08
  beq .backspace
  cmp #0x0a
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


do_scroll:
  stz GD_ROW
  jsr gd_clear_line
  lda #1
  jsr gd_scroll_up
  lda #GD_CHAR_ROWS - 1
  sta GD_ROW
  stz GD_COL
  rts


callback_no_more_chars:
  rts


callback_key_left:
  rts


callback_key_right:
  rts


callback_key_esc:
  rts


callback_key_function:
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


