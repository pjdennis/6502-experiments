;TODO: if code is not on the full list of codes that are understood then ignore it?

  .include base_config_v2.inc

INTERRUPT_ROUTINE       = $3f00

KB_DECODE_BREAK         = %00010000
KB_DECODE_EXTENDED      = %00001000
KB_DECODE_PAUSE_SEQ     = %00000111

KB_MOD_L_SHIFT          = %10000000
KB_MOD_R_SHIFT          = %01000000
KB_MOD_L_CTRL           = %00100000
KB_MOD_R_CTRL           = %00010000
KB_MOD_L_ALT            = %00001000
KB_MOD_R_ALT            = %00000100
KB_MOD_L_GUI            = %00000010
KB_MOD_R_GUI            = %00000001

KB_CODE_BREAK           = $f0
KB_CODE_EXTENDED        = $e0
KB_CODE_EXTENDED_IGNORE = $12
KB_CODE_PAUSE           = $62
KB_CODE_PRT_SCR         = $57

KB_CODE_L_SHIFT         = $12
KB_CODE_R_SHIFT         = $59
KB_CODE_L_CTRL          = $11
KB_CODE_R_CTRL          = $58
KB_CODE_L_ALT           = $19
KB_CODE_R_ALT           = $39
KB_CODE_L_GUI           = $8b
KB_CODE_R_GUI           = $8c

KB_META_SHIFT           = %10000000
KB_META_CTRL            = %01000000
KB_META_ALT             = %00100000
KB_META_GUI             = %00010000
KB_META_EXTENDED        = %00000010
KB_META_BREAK           = %00000001

ASCII_BACKSPACE         = 0x08
ASCII_TILDE             = 0x7e
ASCII_BACKSLASH         = 0x5c

CHARACTER_TILDE         = 1
CHARACTER_BACKSLASH     = 2

CP_M_DEST_P             = $0000 ; 2 bytes
CP_M_SRC_P              = $0002 ; 2 bytes
CP_M_LEN                = $0004 ; 2 bytes
TRANSLATE_TABLE         = $0006 ; 2 bytes
CREATE_CHARACTER_PARAM  = $0008 ; 2 bytes
CONSOLE_CHARACTER_COUNT = $000a ; 1 byte
SIMPLE_BUFFER_WRITE_PTR = $000b ; 1 byte
SIMPLE_BUFFER_READ_PTR  = $000c ; 1 byte
KEYBOARD_RECEIVING      = $000d ; 1 byte
KEYBOARD_DECODE_STATE   = $000e ; 1 byte
KEYBOARD_MODIFIER_STATE = $000f ; 1 byte
KEYBOARD_LATEST_META    = $0010 ; 1 byte
KEYBOARD_LATEST_CODE    = $0011 ; 1 byte

SIMPLE_BUFFER           = $0200 ; 256 bytes
CONSOLE_TEXT            = $0300 ; CONSOLE_LENGTH (32) bytes

  .org $2000                    ; Loader loads programs to this address
  sei                           ; Disable interrupts until we are ready. TODO is to have
                                ; the loader disable interrupts
  jmp initialize_machine        ; Initialize hardware and then jump to program_start

  ; The initialize_machine routine in this include will set up hardware registers and then
  ; jump to program_start. We do not call a subroutine because for some machine designs the
  ; stack is not usable until after the hardware registers have been initialized
  .include initialize_machine_v2.inc
  .include display_routines_8bit.inc
  .include convert_to_hex.inc
  .include full_screen_console.inc
  .include simple_buffer.inc
  .include copy_memory.inc
  .include key_codes.inc

; Custom characters
character_data_tilde:
  .byte %00000
  .byte %00000
  .byte %00000
  .byte %01101
  .byte %10010
  .byte %00000
  .byte %00000
  .byte %00000

character_data_backslash:
  .byte %00000
  .byte %10000
  .byte %01000
  .byte %00100
  .byte %00010
  .byte %00001
  .byte %00000
  .byte %00000

; Code sequence for the pause/break key
kb_seq_pause       .byte $e1, $14, $77, $e1, $f0, $14, $f0, $77, $00

; Mapping from PS/2 code set 3 modifier keys to the bit mask used for tracking modifier states
kb_modifier_codes: .byte KB_CODE_L_SHIFT, KB_CODE_R_SHIFT, KB_CODE_L_CTRL, KB_CODE_R_CTRL
                   .byte KB_CODE_L_ALT,   KB_CODE_R_ALT,   KB_CODE_L_GUI,  KB_CODE_R_GUI, $00
kb_modifier_masks: .byte KB_MOD_L_SHIFT,  KB_MOD_R_SHIFT,  KB_MOD_L_CTRL,  KB_MOD_R_CTRL
                   .byte KB_MOD_L_ALT,    KB_MOD_R_ALT,    KB_MOD_L_GUI,   KB_MOD_R_GUI

; Mapping from the modifier state masks for left/right modifier keys to the mask used to
; indicate at least one of the keys is pressed
kb_modifier_from:  .byte (KB_MOD_L_SHIFT | KB_MOD_R_SHIFT), (KB_MOD_L_CTRL | KB_MOD_R_CTRL)
                   .byte (KB_MOD_L_ALT   | KB_MOD_R_ALT),   (KB_MOD_L_GUI  | KB_MOD_R_GUI), $00
kb_modifier_to     .byte KB_META_SHIFT,                     KB_META_CTRL
                   .byte KB_META_ALT,                       KB_META_GUI

program_start:
  ; Initialize stack
  ldx #$ff
  txs

  ; Initialize functions we will use in this program
  jsr reset_and_enable_display_no_cursor
  jsr console_initialize
  jsr simple_buffer_initialize

  ; Create characters
  lda #CHARACTER_TILDE
  ldx #<character_data_tilde
  ldy #>character_data_tilde
  jsr create_character

  lda #CHARACTER_BACKSLASH
  ldx #<character_data_backslash
  ldy #>character_data_backslash
  jsr create_character

  ; Initialize Keyboard decode state
  stz KEYBOARD_DECODE_STATE
  stz KEYBOARD_MODIFIER_STATE

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

  stz KEYBOARD_RECEIVING

  ; Set up interrupts for detecting start of receipt of byte from keyboard
  lda #PCR_CA2_IND_NEG_E
  sta PCR

  lda #%10000001  ; Enable CA2 interrupt
  sta IER

  ; Enable interrupts so we start recieving data from the keyboard
  cli

; Read and display translated characters from the keyboard
get_char_loop:
  jsr keyboard_get_char
  bcs get_char_loop
get_char_loop_2:
  jsr console_print_character_with_translation
  jsr keyboard_get_char
  bcc get_char_loop_2
  jsr console_show
  bra get_char_loop

;TODO not used
simple_decode_loop:
  jsr simple_buffer_read
  bcs simple_decode_loop
  jsr keyboard_set3_decode
  bcs simple_decode_loop
simple_decode_loop_2:
  lda KEYBOARD_LATEST_META
  jsr console_print_hex
  lda KEYBOARD_LATEST_CODE
  jsr console_print_hex
simple_decode_loop_3:
  jsr simple_buffer_read
  bcs simple_decode_show
  jsr keyboard_set3_decode
  bcs simple_decode_loop_3
  bra simple_decode_loop_2
simple_decode_show:
  jsr console_show
  bra simple_decode_loop

;TODO not used
decode_loop:
  jsr simple_buffer_read
  bcs decode_loop               ; If no byte available jump back to read again
  jsr keyboard_set3_decode
  bcs decode_loop               ; If nothing yet decoded jump back to read again
decode_loop_2:
  lda KEYBOARD_MODIFIER_STATE
  jsr console_print_binary      ; 8 chars -  8
  lda #" "
  jsr console_print_character   ; 1 char  -  9
  lda KEYBOARD_LATEST_META
  jsr console_print_hex         ; 2 chars - 11
  lda KEYBOARD_LATEST_CODE
  jsr console_print_hex         ; 2 chars - 13
  lda #" "
  jsr console_print_character   ; 1 char  - 14
  lda KEYBOARD_LATEST_META
  bit #KB_META_SHIFT
  bne decode_loop_translate_upper
; Lower
  lda KEYBOARD_LATEST_CODE
  jsr keyboard_translate_code_lower
  bra decode_loop_translate_done
decode_loop_translate_upper:
  lda KEYBOARD_LATEST_CODE
  jsr keyboard_translate_code_upper
decode_loop_translate_done:
  bcc decode_loop_show_translation
  lda #" "
decode_loop_show_translation:
  jsr console_print_character   ; 1 char  - 15
  lda #" "
  jsr console_print_character   ; 1 char  - 16
  jsr simple_buffer_read
  bcs decode_show               ; If no byte available jump to show what we have
  jsr keyboard_set3_decode
  bcc decode_loop_2             ; If something decoded jump back to show it
  ; Fall through
decode_show:
  jsr console_show
  bra decode_loop

;TODO not used
show_presses_loop:
  jsr keyboard_get_press
  bcs show_presses_loop               ; If no press available loop to continue reading
show_presses_loop_2:
  jsr console_print_hex
  jsr keyboard_get_press
  bcc show_presses_loop_2             ; Found another press so jump back to print it
  ; No more presses
  jsr console_show
  bra show_presses_loop

;TODO not used
simple_show_loop:
  jsr simple_buffer_read
  bcs simple_show_loop
simple_show_loop_2:
  jsr console_print_hex
  jsr simple_buffer_read
  bcc simple_show_loop_2
  jsr console_show
  bra simple_show_loop


; On exit Carry set if no result so far
;         A contains key code of key press
keyboard_get_press:
keyboard_get_press_repeat:
  jsr simple_buffer_read
  bcs keyboard_get_press_done   ; No keyboard data so we are done
  jsr keyboard_set3_decode
  bcs keyboard_get_press_repeat ; Decoding not yet emitted code so keep reading
  lda KEYBOARD_LATEST_META
  bit #KB_META_BREAK
  bne keyboard_get_press_repeat ; Keyboard break code so keep reading
  ; Found a make code
  lda KEYBOARD_LATEST_CODE
  clc
keyboard_get_press_done:
  rts


; On exit Carry set if no result so far
;         A contains the next char
keyboard_get_char:
keyboard_get_char_repeat:
  jsr simple_buffer_read
  bcs keyboard_get_char_done    ; Exit when input buffer is empty
  jsr keyboard_set3_decode
  bcs keyboard_get_char_repeat  ; Nothing decoded so far so read more
  lda KEYBOARD_LATEST_META
  bit #KB_META_BREAK
  bne keyboard_get_char_repeat  ; Decoded key up event; ignore these so read more
  jsr keyboard_get_latest_translated_code
  bcs keyboard_get_char_repeat  ; No translation for code; ignore these so read more
keyboard_get_char_done:
  rts


; On entry KEYBOARD_LATEST_META contains shift state
;          KEYBOARD_LATEST_CODE contains current key code
; On exit  Carry set if no translation
;          A contains translated code if translation occurred
keyboard_get_latest_translated_code:
  lda KEYBOARD_LATEST_META
  bit #KB_META_SHIFT
  bne keyboard_get_latest_translated_code_translate_upper
; Lower
  lda KEYBOARD_LATEST_CODE
  jsr keyboard_translate_code_lower
  bra keyboard_get_latest_translated_code_done
keyboard_get_latest_translated_code_translate_upper:
  lda KEYBOARD_LATEST_CODE
  jsr keyboard_translate_code_upper
keyboard_get_latest_translated_code_done:
  rts


; On entry A contains the byte from the keyboard
; On exit Carry set if no result so far
;         X, Y are preserved
;         A is not preserved
;         KEYBOARD_LATEST_META contains metadata for latest key event
;         KEYBOARD_LATEST_CODE contains code for latest key event
keyboard_set3_decode:
  jsr keyboard_decode
  bcs keyboard_set3_decode_done ; No data so we are done
  lda KEYBOARD_LATEST_META
  bit #KB_META_EXTENDED
  bne keyboard_set3_decode_extended
  ; Decode normal
  lda KEYBOARD_LATEST_CODE
  jsr keyboard_translate_normal_to_set3
  bra keyboard_set3_translate_done
keyboard_set3_decode_extended:
  and #~KB_META_EXTENDED
  sta KEYBOARD_LATEST_META
  lda KEYBOARD_LATEST_CODE
  jsr keyboard_translate_extended_to_set3
keyboard_set3_translate_done:
  sta KEYBOARD_LATEST_CODE
  jsr keyboard_set3_modifier_track
  jsr keyboard_update_modifiers
  clc
keyboard_set3_decode_done:
  rts


; On entry KEYBOARD_LATEST_META contains latest state (make/break)
;          KEYBOARD_LATEST_CODE contains latest key code
;          KEYBOARD_MODIFIER_STATE contains the current state of modifier keys
; On exit  KEYBOARD_MODIFIER_STATE contains the updated state of modifier keys
;          A, X, Y are preserverd
keyboard_set3_modifier_track:
  pha
  phx
  ldx #$ff
keyboard_set3_modifier_loop:
  inx
  lda kb_modifier_codes, X
  beq keyboard_set3_modifier_track_done
  cmp KEYBOARD_LATEST_CODE
  bne keyboard_set3_modifier_loop
  ; Fall through - code found
  lda KEYBOARD_LATEST_META
  bit #KB_META_BREAK
  bne keyboard_set3_modifier_track_break
  ; Make
  lda kb_modifier_masks, X
  tsb KEYBOARD_MODIFIER_STATE
  bra keyboard_set3_modifier_track_done
keyboard_set3_modifier_track_break:
  lda kb_modifier_masks, X
  trb KEYBOARD_MODIFIER_STATE
  ; Fall through - done
keyboard_set3_modifier_track_done:
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
keyboard_update_modifiers_loop:
  inx
  lda kb_modifier_from, X
  beq keyboard_update_modifiers_done
  bit KEYBOARD_MODIFIER_STATE
  beq keyboard_update_modifiers_break
; Make
  lda kb_modifier_to, X
  tsb KEYBOARD_LATEST_META
  bra keyboard_update_modifiers_loop
keyboard_update_modifiers_break:
  lda kb_modifier_to, X
  trb KEYBOARD_LATEST_META
  bra keyboard_update_modifiers_loop
keyboard_update_modifiers_done:
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
  bne kb_state_pause
  bit #KB_DECODE_BREAK
  bne kb_state_break
  bit #KB_DECODE_EXTENDED
  bne kb_state_extended
  ; Fall through to the initial state (waiting for first byte of sequence)
kb_state_waiting:
  cpx #KB_CODE_BREAK
  beq kb_to_break
  cpx #KB_CODE_EXTENDED
  beq kb_to_extended
  cpx kb_seq_pause              ; The first value in the pause key sequence
  beq kb_to_pause
  ; No special codes identified so current byte is a single byte sequence
  lda #0                        ; Emit non-extended make code
  bra kb_decode_emit

; ---- Handlers for the states ----

; The pause state indicates we are recieving the 8 byte pause sequence
; A = current KEYBOARD_DECODE_STATE
kb_state_pause:
  and #KB_DECODE_PAUSE_SEQ
  phx                          ; Stack <- latest byte from keyboard
  tax                          ; X <- index of current code in sequence
  pla                          ; A <- latest byte from keyboard
  cmp kb_seq_pause, X
  bne kb_pause_error
  inx
  lda kb_seq_pause, X
  beq kb_pause_emit            ; Branch if we reached the last code in sequence
  txa                          ; New pause seq index becomes new state
  bra kb_decode_no_emit
kb_pause_emit:
  lda #0                       ; Emit pause as non-extended make code
  ldx #KB_CODE_PAUSE
  bra kb_decode_emit
; A = latest byte from keyboard
kb_pause_error:
  ; Reset state and reprocess with the current code
  tax
  lda #0
  sta KEYBOARD_DECODE_STATE
  bra kb_state_waiting

kb_state_break:
  bit #KB_DECODE_EXTENDED
  bne kb_state_extended_break
  lda #KB_META_BREAK            ; Emit non-extended break code
  bra kb_decode_emit

kb_state_extended:
  cpx #KB_CODE_BREAK
  beq kb_to_extended_break
  cpx #KB_CODE_EXTENDED_IGNORE
  beq kb_decode_ignore
  lda #KB_META_EXTENDED
  bra kb_decode_emit

kb_state_extended_break:
  cpx #KB_CODE_EXTENDED_IGNORE
  beq kb_decode_ignore
  lda #(KB_META_BREAK | KB_META_EXTENDED)
  bra kb_decode_emit

; ---- State transitions ----

kb_to_break:
  lda #KB_DECODE_BREAK
  bra kb_decode_no_emit

kb_to_extended:
  lda #KB_DECODE_EXTENDED
  bra kb_decode_no_emit

kb_to_extended_break:
  lda #(KB_DECODE_EXTENDED | KB_DECODE_BREAK)
  bra kb_decode_no_emit

kb_to_pause:
  lda #%00000001                ; Start pause sequence counter at 1
  bra kb_decode_no_emit

; ---- Exiting the routine with result or no result ----

; A = Metadata
; X = code
kb_decode_emit:
  sta KEYBOARD_LATEST_META
  stx KEYBOARD_LATEST_CODE
  stz KEYBOARD_DECODE_STATE
  clc
  bra kb_decode_done

; Ignore current code and go back to initial state
kb_decode_ignore:
  lda #0
  ; Fall through

; A = new decode state
kb_decode_no_emit:
  sta KEYBOARD_DECODE_STATE
  sec
  ; Fall through

kb_decode_done:
  plx
  rts


; On entry A contains the PS/2 set 2 non-extended "normal" keyboard code
; On exit  A contains the PS/2 set 3 keyboard code
;          X, Y are preserverd
keyboard_translate_normal_to_set3:
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
keyboard_translate_extended_to_set3:
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
; On exit  A contains the translated code or original code if no translation found
;          X, Y are not preserved
code_translate:
  stx TRANSLATE_TABLE
  sty TRANSLATE_TABLE + 1
  tax
  ldy #0
  bra code_translate_loop_entry
code_translate_loop:
  iny
  iny
code_translate_loop_entry:
  lda (TRANSLATE_TABLE), Y
  beq code_translate_not_found
  txa
  cmp (TRANSLATE_TABLE), Y
  bne code_translate_loop
  ; Code found
  iny
  lda (TRANSLATE_TABLE), Y
  bra code_translate_done
code_translate_not_found:
  txa
code_translate_done:
  rts


; On entry A contains the keyboard code
; On exit  A contains the translated code or 0 if no translation available
;          X, Y are preserved
keyboard_translate_code_lower:
  phx
  phy
  ldx #<key_codes_lower
  ldy #>key_codes_lower
  jsr table_lookup
  ply
  plx
  rts


; On entry A contains the keyboard code
; On exit  A contains the translated code or 0 if no translation available
;          X, Y are preserved
keyboard_translate_code_upper:
  phx
  phy
  ldx #<key_codes_upper
  ldy #>key_codes_upper
  jsr table_lookup
  ply
  plx
  rts


; On entry A contains the code
;          X, Y contains the address of the tranlsation table which starts with the length
; On exit  Carry is set if no translation was found
;          A contains the translated code if translation found
;          X, Y are not guaranteed to be preserved
table_lookup:
  stx TRANSLATE_TABLE
  sty TRANSLATE_TABLE + 1
  cmp (TRANSLATE_TABLE)
  bcs table_lookup_no_match
  phy
  tay
  iny
  lda (TRANSLATE_TABLE), Y
  ply
  cmp #0
  beq table_lookup_no_match
  clc
  bra table_lookup_done
table_lookup_no_match:
  sec
table_lookup_done:
  rts


; On entry A = character to print to console
; On exit  X, Y are preserved
;          A is not preserved
console_print_character_with_translation:
  cmp #ASCII_BACKSPACE
  beq console_print_character_with_backspace_backspace
  jsr translate_character_for_display
  jmp console_print_character ; tail call
console_print_character_with_backspace_backspace:
  jmp console_backspace ; tail call


; On entry A = byte to print to console in hex
; On exit  X, Y are preserved
;          A is not preserved
console_print_hex:
  phx
  jsr convert_to_hex
  jsr console_print_character
  txa
  jsr console_print_character
  plx
  rts


; On entry A contains the value to display in binary
; On exit  A, X, Y are preserved
console_print_binary:
  pha
  phx
  phy

  ldx #8
console_print_binary_loop:
  asl
  tay
  bcs console_print_binary_one
  lda #'0'
  bra console_print_binary_continue
console_print_binary_one:
  lda #'1'
console_print_binary_continue:
  jsr console_print_character
  tya
  dex
  bne console_print_binary_loop

  ply
  plx
  pla
  rts


; On entry A is an ASCII character
; On exit  A is translated to the custom char code if applicable
translate_character_for_display:
  cmp #ASCII_TILDE
  beq translate_character_for_display_tilde
  cmp #ASCII_BACKSLASH
  beq translate_character_for_display_backslash
  bra translate_character_for_display_done
translate_character_for_display_tilde:
  lda #CHARACTER_TILDE
  bra translate_character_for_display_done
translate_character_for_display_backslash:
  lda #CHARACTER_BACKSLASH
  ; fall through to done
translate_character_for_display_done:
  rts


;On entry A = character number
;         X = low byte source address
;         Y = high byte source address
;On exit  A, X, Y are not preserved
create_character:
  stx CREATE_CHARACTER_PARAM
  sty CREATE_CHARACTER_PARAM + 1

  asl
  asl
  asl
  ora #CMD_SET_CGRAM_ADDRESS
  jsr display_command

  ldy #0
create_character_loop:
  lda (CREATE_CHARACTER_PARAM), Y
  jsr display_character

  iny
  cpy #8
  bne create_character_loop

  rts


interrupt:
  pha
  phx

  lda #%00000001  ; Clear the CA2 interrupt
  sta IFR

  lda KEYBOARD_RECEIVING
  beq interrupt_start_receiving
  lda #PCR_CA2_IND_NEG_E
  sta PCR
  STZ KEYBOARD_RECEIVING

  ldx DDRB        ; Save DDRB to X

  lda #%00000000
  sta DDRB        ; Set PORTB to input

  lda #SOEB
  trb PORTA       ; Enable shift register output

  lda PORTB
  jsr simple_buffer_write

  lda #SOEB
  tsb PORTA       ; Disable shift register output

  stx DDRB        ; Restore DDRB from X
  bra interrupt_done

interrupt_start_receiving:
  lda #PCR_CA2_IND_POS_E
  sta PCR
  lda #1
  sta KEYBOARD_RECEIVING

interrupt_done:
  plx
  pla
  rti
interrupt_end:
