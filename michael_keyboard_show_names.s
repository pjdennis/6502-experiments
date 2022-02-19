;TODO: If code is not on the full list of codes that are understood then ignore it?
;      12/8/21 This might be related to key codes that don't map over to set 3. Currently
;      they will not translate to ASCII, but if we look at raw key codes they won't be
;      filtered out

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

CP_M_DEST_P              = $0000 ; 2 bytes
CP_M_SRC_P               = $0002 ; 2 bytes
CP_M_LEN                 = $0004 ; 2 bytes
TRANSLATE_TABLE          = $0006 ; 2 bytes
CREATE_CHARACTER_PARAM   = $0008 ; 2 bytes
CONSOLE_CURSOR_POSITION  = $000a ; 1 byte
SIMPLE_BUFFER_WRITE_PTR  = $000b ; 1 byte
SIMPLE_BUFFER_READ_PTR   = $000c ; 1 byte
KEYBOARD_RECEIVING       = $000d ; 1 byte
KEYBOARD_DECODE_STATE    = $000e ; 1 byte
KEYBOARD_LOCK_STATE      = $000f ; 1 byte
KEYBOARD_MODIFIER_STATE  = $0010 ; 1 byte
KEYBOARD_LATEST_META     = $0011 ; 1 byte
KEYBOARD_LATEST_CODE     = $0012 ; 1 byte
SENDING_TO_KEYBOARD      = $0013 ; 1 byte
ACK_RECEIVED             = $0014 ; 1 byte

TEMP_ZP_BYTE_1           = $0015 ; 1 byte
TEMP_ZP_BYTE_2           = $0016 ; 1 byte
TEMP_ZP_BYTE_3           = $0017 ; 1 byte

DISPLAY_STRING_PARAM     = $0018 ; 2 bytes

SIMPLE_BUFFER            = $0200 ; 256 bytes
CONSOLE_TEXT             = $0300 ; CONSOLE_LENGTH + 1 bytes

  .org $2000                     ; Loader loads programs to this address
  jmp initialize_machine         ; Initialize hardware and then jump to program_start

  ; The initialize_machine routine in this include will set up hardware registers and then
  ; jump to program_start. We do not call a subroutine because for some machine designs the
  ; stack is not usable until after the hardware registers have been initialized
  .include delay_routines.inc
  .include initialize_machine_v2.inc
EXTEND_CHARACTER_SET = 1
  .include display_routines.inc
CONSOLE_WIDTH = DISPLAY_WIDTH
CONSOLE_HEIGHT = DISPLAY_HEIGHT
  .include full_screen_console_flexible_line_based.inc
  .include simple_buffer.inc
  .include copy_memory.inc
  .include key_codes.inc
  .include convert_to_hex.inc

  .include display_string.inc
  .include key_names.inc

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

  ; Initialize functions we will use in this program
  jsr reset_and_enable_display_no_cursor
  jsr console_initialize
  jsr simple_buffer_initialize

  ; Initialize Keyboard decode state
  stz KEYBOARD_DECODE_STATE
  stz KEYBOARD_MODIFIER_STATE
  stz KEYBOARD_LOCK_STATE


  ;lda #KEY_F1
  ;jsr print_key_name_to_console
  ;lda #$fe
  ;jsr print_key_name_to_console
  ;jsr console_show
  ;stp


  ;lda #KEY_RESERVED
  ;jsr name_lookup
  ;jsr console_print_string
  ;lda #'\n'
  ;jsr console_print_character
  ;lda #KEY_F1
  ;jsr name_lookup
  ;jsr console_print_string
  ;jsr console_show
  ;stp


  ; Relocate the interrupt handler. The EEPROM has a fixed address, INTERRUPT_ROUTINE
  ; for the interrupt routine so copy the handler there
  lda #<INTERRUPT_ROUTINE
  sta CP_M_DEST_P
  lda #>INTERRUPT_ROUTINE
  sta CP_M_DEST_P + 1
  lda #<interrupt
  sta CP_M_SRC_P
  lda #>interrupt
  sta CP_M_SRC_P + 1
  lda #<(interrupt_end - interrupt)
  sta CP_M_LEN
  lda #>(interrupt_end - interrupt)
  sta CP_M_LEN + 1
  jsr copy_memory

  ; Initialize flags
  stz KEYBOARD_RECEIVING
  stz SENDING_TO_KEYBOARD
  stz ACK_RECEIVED

  ; Set up interrupts for detecting start of receipt of byte from keyboard
  lda #PCR_CA2_IND_NEG_E
  sta PCR

  lda #%10000001  ; Enable CA2 interrupt
  sta IER

  ; Enable interrupts so we start recieving data from the keyboard
  cli

  ; Initialize keyboard
  lda #KB_COMMAND_ENABLE
  jsr keyboard_send_command

  lda #KB_COMMAND_SET_TYPEMATIC
  jsr keyboard_send_command

  lda #0 ; Fastest rate (30 cps) + shortest delay (0.25 seconds)
  jsr keyboard_send_command

  lda #0
  jsr keyboard_set_leds


;keyboard_to_console_as_hex:
;.loop:
;  jsr console_show
;.wait_loop:
;  jsr simple_buffer_read
;  bcs .wait_loop
;  jsr console_print_hex
;  bra .loop


;keyboard_decoded_to_console_as_hex:
;.loop
;  jsr console_show
;.repeat:
;  jsr simple_buffer_read
;  bcs .repeat                   ; Exit when input buffer is empty
;  jsr keyboard_decode_and_translate_to_set_3
;  bcs .repeat                   ; Nothing decoded so far so read more
;  lda KEYBOARD_LATEST_META
;  bit #KB_META_BREAK
;  bne .repeat                   ; Decoded key up event; ignore these so read more
;  lda KEYBOARD_LATEST_CODE
;  jsr console_print_hex
;  bra .loop


keyboard_decoded_to_console_as_name:
.loop
  jsr console_show
.repeat:
  jsr simple_buffer_read
  bcs .repeat                   ; Exit when input buffer is empty
  jsr keyboard_decode_and_translate_to_set_3
  bcs .repeat                   ; Nothing decoded so far so read more
  lda KEYBOARD_LATEST_META
  bit #KB_META_BREAK
  bne .repeat                   ; Decoded key up event; ignore these so read more
  lda KEYBOARD_LATEST_CODE
  jsr print_key_name_to_console
  bra .loop


  jsr clear_console

  ; Read and display translated characters from the keyboard
get_char_loop:
  jsr keyboard_get_char
  bcs get_char_loop
get_char_loop_2:
  jsr console_print_character
  jsr keyboard_get_char
  bcc get_char_loop_2
  jsr console_show
  bra get_char_loop


clear_console:
  pha
  jsr console_clear
  ; Show prompt
  lda #">"
  jsr console_print_character
  jsr console_show
  pla
  rts


console_print_hex:
  phx
  phy

  jsr convert_to_hex
  jsr console_print_character
  txa
  jsr console_print_character

  jsr console_get_cursor_xy
  cpx #0
  beq .done

;  lda #' '
;  jsr console_print_character

.done:
  ply
  plx
  rts


; On exit Carry set if no result so far
;         A contains the next char
;         X, Y are preserved
keyboard_get_char:
.repeat:
  jsr simple_buffer_read
  bcs .done                     ; Exit when input buffer is empty
  jsr keyboard_decode_and_translate_to_set_3
  bcs .repeat                   ; Nothing decoded so far so read more
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
  jsr console_cursor_left
  bra .handled
.key_right:
  jsr console_cursor_right
  bra .handled
.key_esc:
  jsr clear_console
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
  jsr keyboard_caps_lock_track
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
keyboard_caps_lock_track:
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


; Requires DISPLAY_STRING_PARAM - 2 bytes for temporary storage of parameters

; On entry A, X contain low and high bytes of string address
; On exit A, X, Y are preserved
console_print_string:
  pha
  phx
  phy

  sta DISPLAY_STRING_PARAM
  stx DISPLAY_STRING_PARAM + 1
  ldy #0
.print_loop:
  lda (DISPLAY_STRING_PARAM),Y
  beq .done_printing
  jsr console_print_character
  iny
  bra .print_loop
.done_printing:

  ply
  plx
  pla
  rts


; On entry A contains the key code
; On exit A, X, Y are preserved
print_key_name_to_console:
  pha
  phx
  phy
  tay
  jsr name_lookup
  bcs .not_found
  jsr console_print_string
  bra .printed
.not_found
  lda #<unrecognized_key_message
  ldx #>unrecognized_key_message
  jsr console_print_string
  tya
  jsr console_print_hex
.printed
  lda #'\n'
  jsr console_print_character
  ply
  plx
  pla
  rts

unrecognized_key_message: .asciiz 'Unknown Code: '

; On entry A contains the key code
; On exit  A, X contains the low and high bytes of the string address
;          Y is preserved
;          Carry is set if no translation found
name_lookup:
.POINTER_L    = TEMP_ZP_BYTE_1
.POINTER_H    = TEMP_ZP_BYTE_2
.TARGET_VALUE = TEMP_ZP_BYTE_3
  phy
  sta .TARGET_VALUE
  stz .POINTER_L
  lda #>key_names
  sta .POINTER_H
  ldy #<key_names
.word_loop:
  lda (.POINTER_L), Y
  cmp .TARGET_VALUE
  beq .found
.skip_loop:
  iny
  bne .skip_loop_high_ready
  inc .POINTER_H
.skip_loop_high_ready:
  lda (.POINTER_L), Y
  bne .skip_loop
; terminating zero found; check for another zero
  iny
  bne .skip_loop_high_ready_2
  inc .POINTER_H
.skip_loop_high_ready_2:
  lda (.POINTER_L), Y
  bne .word_loop
; not found
  sec
  bra .done
.found:
  iny
  bne .found_high_ready
  inc .POINTER_H
.found_high_ready:
  tya
  ldx .POINTER_H
  clc
.done:
  ply
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
