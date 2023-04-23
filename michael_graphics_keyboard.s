  .include base_config_v2.inc

INTERRUPT_ROUTINE        = $3f00

KB_DECODE_BREAK          = %00010000
KB_DECODE_EXTENDED       = %00001000
KB_DECODE_PAUSE_SEQ      = %00000111

KB_CAPS_LOCK_ON          = %00000001
KB_SCROLL_LOCK_ON        = %00000010
KB_NUM_LOCK_ON           = %00000100
KB_CAPS_LOCK_DOWN        = %00001000
KB_SCROLL_LOCK_DOWN      = %00010000
KB_NUM_LOCK_DOWN         = %00100000

KB_MOD_L_SHIFT           = %10000000
KB_MOD_R_SHIFT           = %01000000
KB_MOD_L_CTRL            = %00100000
KB_MOD_R_CTRL            = %00010000
KB_MOD_L_ALT             = %00001000
KB_MOD_R_ALT             = %00000100
KB_MOD_L_GUI             = %00000010
KB_MOD_R_GUI             = %00000001

KB_COMMAND_SET_LEDS      = $ed
KB_COMMAND_ECHO          = $ee
KB_COMMAND_READ_ID       = $f2
KB_COMMAND_SET_TYPEMATIC = $f3
KB_COMMAND_ENABLE        = $f4
KB_COMMAND_RESET         = $ff
KB_COMMAND_ACK           = $fa

KB_LED_SCROLL_LOCK       = %00000001
KB_LED_NUM_LOCK          = %00000010
KB_LED_CAPS_LOCK         = %00000100

KB_CODE_BREAK            = $f0
KB_CODE_EXTENDED         = $e0
KB_CODE_EXTENDED_IGNORE  = $12

KB_META_SHIFT            = %10000000
KB_META_CTRL             = %01000000
KB_META_ALT              = %00100000
KB_META_GUI              = %00010000
KB_META_EXTENDED         = %00000010
KB_META_BREAK            = %00000001

CP_M_DEST_P              = $00 ; 2 bytes
CP_M_SRC_P               = $02 ; 2 bytes
CP_M_LEN                 = $04 ; 2 bytes

TRANSLATE_TABLE          = $06 ; 2 bytes
CREATE_CHARACTER_PARAM   = $08 ; 2 bytes
SIMPLE_BUFFER_WRITE_PTR  = $0a ; 1 byte
SIMPLE_BUFFER_READ_PTR   = $0b ; 1 byte
KEYBOARD_RECEIVING       = $0c ; 1 byte
KEYBOARD_DECODE_STATE    = $0d ; 1 byte
KEYBOARD_LOCK_STATE      = $0e ; 1 byte
KEYBOARD_MODIFIER_STATE  = $0f ; 1 byte
KEYBOARD_LATEST_META     = $10 ; 1 byte
KEYBOARD_LATEST_CODE     = $11 ; 1 byte
SENDING_TO_KEYBOARD      = $12 ; 1 byte
ACK_RECEIVED             = $13 ; 1 byte

DISPLAY_STRING_PARAM     = $14 ; 2 bytes
TEXT_PTR                 = $16 ; 2 bytes
TEXT_PTR_NEXT            = $18 ; 2 bytes
SCROLL_OFFSET            = $1a ; 2 bytes
LINE_CHARS_REMAINING     = $1c ; 1 byte
GD_ZERO_PAGE_BASE        = $1d ; ? bytes

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


; On exit Carry set if no result so far
;         A contains the next char
;         X, Y are preserved
keyboard_get_char:
.repeat:
  jsr simple_buffer_read
  bcs .done                     ; Exit when input buffer is empty
  jsr keyboard_decode_and_translate_to_set_3
  bcs .repeat                   ; Nothing decoded so far so read more
  jsr keyboard_lock_keys_track
  lda KEYBOARD_LATEST_META
  bit #KB_META_BREAK
  bne .repeat                   ; Decoded key up event; ignore these so read more
  jsr handle_special_keys
  bcs .repeat                   ; Movement key handled; read more
  jsr keyboard_get_latest_ascii
  bcs .repeat                   ; No translation for code; ignore these so read more
.done:
  rts


; On entry KEYBOARD_LATEST_CODE contains the latest key code
; On exit  C is set if key was handled
;          A is not preserved
;          X, Y are preserved
handle_special_keys:
  lda KEYBOARD_LATEST_CODE
  cmp #KEY_LEFT
  beq .key_left
  cmp #KEY_RIGHT
  beq .key_right
  cmp #KEY_ESC
  beq .key_esc

  cmp #KEY_F1
  beq .key_function

  lda KEYBOARD_LOCK_STATE
  bit #KB_NUM_LOCK_ON
  beq .check_keypad

  lda KEYBOARD_LATEST_META
  bit #KB_META_SHIFT
  beq .not_handled

.check_keypad:
  lda KEYBOARD_LATEST_CODE
  cmp #KEY_KP4
  beq .key_left
  cmp #KEY_KP6
  beq .key_right

.not_handled:
  clc
  rts                      ; Return - not handled
.key_left:
  jsr callback_key_left
  bra .handled
.key_right:
  jsr callback_key_right
  bra .handled
.key_esc:
  jsr callback_key_esc
  bra .handled
.key_function:
  jsr callback_key_function
.handled:
  sec
  rts                      ; Return - handled


; On entry KEYBOARD_LATEST_META contains shift state
;          KEYBOARD_LATEST_CODE contains current key code
; On exit  Carry set if no translation
;          A contains translated code if translation occurred
keyboard_get_latest_ascii:
  phx
  phy

  lda KEYBOARD_LATEST_CODE
  ldx #<kb_kp_ascii_fixed_translation_table
  ldy #>kb_kp_ascii_fixed_translation_table
  jsr code_translate
  bcc .done

  lda KEYBOARD_LOCK_STATE
  bit #KB_NUM_LOCK_ON
  beq .check_main_ascii

  lda KEYBOARD_LATEST_META
  bit #KB_META_SHIFT
  bne .check_main_ascii

  lda KEYBOARD_LATEST_CODE
  ldx #<kb_kp_ascii_num_translation_table
  ldy #>kb_kp_ascii_num_translation_table
  jsr code_translate
  bcc .done

.check_main_ascii:
  lda KEYBOARD_LATEST_CODE
  ldx #<kb_ascii_translation_table
  ldy #>kb_ascii_translation_table
  jsr code_translate
  bcs .done

  tax
  lda KEYBOARD_LATEST_META
  bit #KB_META_SHIFT
  bne .translate_shifted
  lda KEYBOARD_LOCK_STATE
  bit #KB_CAPS_LOCK_ON
  bne .translate_to_upper
; Unshifted
  txa
  bra .translated
.translate_shifted:
  txa
  ldx #<kb_shift_translation_table
  ldy #>kb_shift_translation_table
  jsr code_translate
  tax
.translate_to_upper:
  txa
  cmp #'a'
  bcc .translated
  cmp #('z' + 1)
  bcs .translated
  sec
  sbc #('a' - 'A')
.translated
  clc ; translation found
.done:
  ply
  plx
  rts


; On entry A contains the byte from the keyboard
; On exit Carry set if no result so far
;         A is the latest set 3 key code if found
;         X, Y are preserved
;         KEYBOARD_LATEST_META contains metadata for latest key event
;         KEYBOARD_LATEST_CODE contains code for latest key event
keyboard_decode_and_translate_to_set_3:
  jsr keyboard_decode
  bcs .decode_done              ; No data so we are done
  lda KEYBOARD_LATEST_META
  bit #KB_META_EXTENDED
  bne .decode_extended
; Decode normal
  lda KEYBOARD_LATEST_CODE
  jsr keyboard_translate_normal
  bra .translate_done
.decode_extended:
  and #~KB_META_EXTENDED
  sta KEYBOARD_LATEST_META
  lda KEYBOARD_LATEST_CODE
  jsr keyboard_translate_extended
.translate_done:
  cmp #0
  bne .code_found
; No translation
  sec
  bra .decode_done
.code_found:
  sta KEYBOARD_LATEST_CODE
  jsr keyboard_modifier_track
  jsr keyboard_update_modifiers
  clc
.decode_done:
  rts


; On entry KEYBOARD_LATEST_META contains latest state (make/break)
;          KEYBOARD_LATEST_CODE contains latest key code
;          KEYBOARD_LOCK_STATE contains current state of lock keys
; On exit  KEYBOARD_LOCK_STATE contains the new state of lock keys
;          A, X, Y are preserved
keyboard_lock_keys_track:
  pha
  phx
  ldx #$ff
.repeat
  inx
  lda kb_lock_codes, X
  beq .done
  cmp KEYBOARD_LATEST_CODE
  bne .repeat
; Code found
  lda KEYBOARD_LATEST_META
  bit #KB_META_BREAK
  bne .key_break
; Key make
  lda kb_lock_down_masks, X
  bit KEYBOARD_LOCK_STATE
  bne .done                    ; Nothing to do - key was already down
; Key going down
  tsb KEYBOARD_LOCK_STATE      ; Set the 'down' flag
  lda kb_lock_on_masks, X
  eor KEYBOARD_LOCK_STATE      ; Toggle the 'on' flag
  sta KEYBOARD_LOCK_STATE
  jsr update_lock_leds
  bra .done
.key_break:
  lda kb_lock_down_masks, X
  trb KEYBOARD_LOCK_STATE
.done:
  plx
  pla
  rts


; On entry KEYBOARD_LOCK_STATE contains the current state of lock keys
; On exit  A, X, Y are preserved
update_lock_leds:
  pha
  phx
  phy
  ldy #0                        ; Y stores the keyboard LED mask
  ldx #$ff
.repeat
  inx
  lda kb_lock_on_masks, X
  beq .set_leds
  bit KEYBOARD_LOCK_STATE
  beq .repeat
; LED on
  tya
  ora kb_lock_to_led, X
  tay
  bra .repeat
.set_leds:
  tya
  jsr keyboard_set_leds
  ply
  plx
  pla
  rts


; On entry KEYBOARD_LATEST_META contains latest state (make/break)
;          KEYBOARD_LATEST_CODE contains latest key code
;          KEYBOARD_MODIFIER_STATE contains the current state of modifier keys
; On exit  KEYBOARD_MODIFIER_STATE contains the updated state of modifier keys
;          A, X, Y are preserverd
keyboard_modifier_track:
  pha
  phx
  ldx #$ff
.repeat:
  inx
  lda kb_modifier_codes, X
  beq .done
  cmp KEYBOARD_LATEST_CODE
  bne .repeat
; Code found
  lda KEYBOARD_LATEST_META
  bit #KB_META_BREAK
  bne .key_break
; Key make
  lda kb_modifier_masks, X
  tsb KEYBOARD_MODIFIER_STATE
  bra .done
.key_break:
  lda kb_modifier_masks, X
  trb KEYBOARD_MODIFIER_STATE
.done:
  plx
  pla
  rts


; On entry KEYBOARD_MODIFIER_STATE contains the current state of modifiers
;          KEYBOARD_LATEST_META contains current meta state without modifiers
; On exit  KEYBOARD_LATEST_META contains new meta state with modifiers
;          A, X, Y are preserved
keyboard_update_modifiers:
  pha
  phx
  ldx #$ff
.repeat:
  inx
  lda kb_modifier_from, X
  beq .done
  bit KEYBOARD_MODIFIER_STATE
  beq .key_break
; Key make
  lda kb_modifier_to, X
  tsb KEYBOARD_LATEST_META
  bra .repeat
.key_break:
  lda kb_modifier_to, X
  trb KEYBOARD_LATEST_META
  bra .repeat
.done:
  plx
  pla
  rts


; On entry  A contains the byte from the keyboard
;           KEYBOARD_DECODE_STATE contains the current state of the decode state machine
; On exit   Carry set if no result so far
;           X, Y are preserved
;           A is not preserved
;           KEYBOARD_LATEST_META contains metadata for latest key event
;           KEYBOARD_LATEST_CODE contains code for latest key event
; Variables KEYBOARD_DECODE_STATE is utlilized and then updated with the new state
keyboard_decode:
  phx
  tax                          ; X <- latest byte from keyboard
  ; Branch to the handler code for the current state
  lda KEYBOARD_DECODE_STATE
  bit #KB_DECODE_PAUSE_SEQ
  bne .state_pause
  bit #KB_DECODE_BREAK
  bne .state_break
  bit #KB_DECODE_EXTENDED
  bne .state_extended
  ; Fall through to the initial state (waiting for first byte of sequence)
.state_waiting:
  cpx #KB_CODE_BREAK
  beq .to_break
  cpx #KB_CODE_EXTENDED
  beq .to_extended
  cpx kb_seq_pause             ; The first value in the pause key sequence
  beq .to_pause
  ; No special codes identified so current byte is a single byte sequence
  lda #0                       ; Emit non-extended make code
  bra .emit

; ---- Handlers for the states ----

; The pause state indicates we are recieving the 8 byte pause sequence
; A = current KEYBOARD_DECODE_STATE
.state_pause:
  and #KB_DECODE_PAUSE_SEQ
  phx                          ; Stack <- latest byte from keyboard
  tax                          ; X <- index of current code in sequence
  pla                          ; A <- latest byte from keyboard
  cmp kb_seq_pause, X
  bne .pause_error
  inx
  lda kb_seq_pause, X
  beq .pause_emit               ; Branch if we reached the last code in sequence
  txa                           ; New pause seq index becomes new state
  bra .no_emit
.pause_emit:
  lda #0                        ; Emit pause as non-extended make code from set 3
  ldx #KEY_PAUSE
  bra .emit
; A = latest byte from keyboard
.pause_error:
  ; Reset state and reprocess with the current code
  tax
  lda #0
  sta KEYBOARD_DECODE_STATE
  bra .state_waiting

.state_break:
  bit #KB_DECODE_EXTENDED
  bne .state_extended_break
  lda #KB_META_BREAK             ; Emit non-extended break code
  bra .emit

.state_extended:
  cpx #KB_CODE_BREAK
  beq .to_extended_break
  cpx #KB_CODE_EXTENDED_IGNORE
  beq .ignore
  lda #KB_META_EXTENDED
  bra .emit

.state_extended_break:
  cpx #KB_CODE_EXTENDED_IGNORE
  beq .ignore
  lda #(KB_META_BREAK | KB_META_EXTENDED)
  bra .emit

; ---- State transitions ----

.to_break:
  lda #KB_DECODE_BREAK
  bra .no_emit

.to_extended:
  lda #KB_DECODE_EXTENDED
  bra .no_emit

.to_extended_break:
  lda #(KB_DECODE_EXTENDED | KB_DECODE_BREAK)
  bra .no_emit

.to_pause:
  lda #%00000001                 ; Start pause sequence counter at 1
  bra .no_emit

; ---- Exiting the routine with result or no result ----

; A = Metadata
; X = code
.emit:
  sta KEYBOARD_LATEST_META
  stx KEYBOARD_LATEST_CODE
  stz KEYBOARD_DECODE_STATE
  clc
  bra .done

; Ignore current code and go back to initial state
.ignore:
  lda #0
  ; Fall through

; A = new decode state
.no_emit:
  sta KEYBOARD_DECODE_STATE
  sec
  ; Fall through

.done:
  plx
  rts


; On entry A contains the PS/2 set 2 non-extended "normal" keyboard code
; On exit  A contains the PS/2 set 3 keyboard code
;          X, Y are preserverd
keyboard_translate_normal:
  phx
  phy
  ldx #<kb_normal_translation_table
  ldy #>kb_normal_translation_table
  jsr code_translate
  ply
  plx
  rts


; On entry A contains the PS/2 set 2 extended keyboard code
; On exit  A contains the PS/2 set 3 keyboard code
;          X, Y are preserverd
keyboard_translate_extended:
  phx
  phy
  ldx #<kb_extended_translation_table
  ldy #>kb_extended_translation_table
  jsr code_translate
  ply
  plx
  rts


; On entry A contains the code
;          X, Y contains the address of the translation table
; On exit  Carry is set if no translation was found
;          A contains the translated code or original code if no translation found
;          X, Y are not preserved
code_translate:
  stx TRANSLATE_TABLE
  sty TRANSLATE_TABLE + 1
  tax
  ldy #0
  bra .repeat_entry
.repeat:
  iny
  iny
.repeat_entry:
  lda (TRANSLATE_TABLE), Y
  beq .not_found
  txa
  cmp (TRANSLATE_TABLE), Y
  bne .repeat
  ; Code found
  iny
  lda (TRANSLATE_TABLE), Y
  clc
  bra .done
.not_found:
  txa
  sec
.done:
  rts


; On entry A = LED flags to set
; On exit  A, X, Y are preserved
keyboard_set_leds:
  phx
  tax
  lda #KB_COMMAND_SET_LEDS
  jsr keyboard_send_command
  txa
  jsr keyboard_send_command
  plx
  rts


; On entry A = command byte to send
; On exit  X, Y are preserverd
;          A is not preserved
keyboard_send_command:
  phx
  phy
  tax                            ; Save command byte in X
.wait_for_not_receiving:
  sei
  lda KEYBOARD_RECEIVING
  beq .not_receiving
  cli
  bra .wait_for_not_receiving
.not_receiving:
  lda #SOLB
  trb PORTA                      ; Pull clock low
  lda #ICA2
.wait_for_interrupt:
  bit IFR
  beq .wait_for_interrupt
  sta IFR
  cli
  stz PCR

  lda #1                         ; 100 microseconds = 0.1 milliseconds = 1 1/10,000 of a second
  jsr delay_10_thousandths

  ldy PORTA                      ; Save PORTA value to Y

  lda #(PARITY | START)
  trb PORTA                      ; Clear parity and start bits

  txa                            ; Retrieve command byte from X
  jsr calculate_parity
  bcs odd_parity
; even parity
  lda #PARITY
  bra parity_mask_ready
odd_parity:
  lda #0
parity_mask_ready:               ; Mask is in A
  tsb PORTA
  stx PORTB                      ; Command byte
  lda #1
  sta SENDING_TO_KEYBOARD        ; Set flag to indicate we are sending
  lda #SOLB
  tsb PORTA                      ; Allow clock to float high; latch output data
  tya
  ora #SOLB
  sta PORTA                      ; Restore PORTA

  lda #3                         ; Wait for long enough that clock line has gone high
  jsr delay_10_thousandths

  lda #PCR_CA2_IND_POS_E
  sta PCR
  lda #1
  sta KEYBOARD_RECEIVING

  ; Wait for send to complete
.wait_for_send:
  lda SENDING_TO_KEYBOARD
  bne .wait_for_send

  ; Wait for ACK
.wait_for_ack:
  lda ACK_RECEIVED
  beq .wait_for_ack

  ply
  plx
  rts


; On entry A = value to calculate parity for
; On exit Carry set for odd parity or clear for even parity
;         A, X, Y are preserved
calculate_parity:
  pha
  phx
  phy

  ldy #0
  ldx #8
.repeat:
  lsr
  bcc .parity_updated            ; Current bit is 0 - do not increment parity
  iny                            ; Current bit is 1 - increment parity
.parity_updated:
  dex
  bne .repeat
  tya
  lsr ; shift parity into carry flag

  ply
  plx
  pla
  rts


interrupt:
  pha

  lda #%00000001  ; Clear the CA2 interrupt
  sta IFR

  lda KEYBOARD_RECEIVING
  beq .start_receiving
  lda #PCR_CA2_IND_NEG_E
  sta PCR
  STZ KEYBOARD_RECEIVING

; Save PORTA data and direction to stack
  lda PORTA
  pha
  lda DDRA
  pha
; Save PORTB data and direction to stack
  lda PORTB
  pha
  lda DDRB
  pha

  lda #%00000000
  sta DDRB                       ; Set PORTB to input

  lda #(ACK | PARITY)
  trb DDRA                       ; Input from the ACK and parity bits

  lda #SOEB
  trb PORTA                      ; Enable shift register output

  lda SENDING_TO_KEYBOARD
  beq .not_sending
;Sending
  dec SENDING_TO_KEYBOARD
  bne .done_checking_send        ; Skip first interrupt which results from pulling clock low
;Sent
  stz ACK_RECEIVED
  bra .done_checking_send
.not_sending:
  lda PORTB
  eor #$ff
  cmp #KB_COMMAND_ACK
  beq .ack_received
;Not ACK
  jsr simple_buffer_write
  bra .done_checking_ack
.ack_received:
  inc ACK_RECEIVED
.done_checking_ack:
.done_checking_send:
  lda #SOEB
  tsb PORTA                      ; Disable shift register output

; Restore PORTB direction and data from stack
  pla
  sta DDRB
  pla
  sta PORTB
; Restore PORTA direction and data from stack
  pla
  sta DDRA
  pla
  sta PORTA

  bra .done

.start_receiving:
  lda #PCR_CA2_IND_POS_E
  sta PCR
  lda #1
  sta KEYBOARD_RECEIVING

.done:
  pla
  rti
interrupt_end:

