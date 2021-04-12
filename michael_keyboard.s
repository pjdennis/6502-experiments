  .include base_config_v2.inc

INTERRUPT_ROUTINE       = $3f00

KB_DECODE_BREAK         = %10000000
KB_DECODE_EXTENDED      = %01000000
KB_DECODE_PAUSE         = %00100000
KB_DECODE_SEQUENCE      = %00000111

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

DISPLAY_STRING_PARAM    = $0000 ; 2 bytes
CP_M_DEST_P             = $0002 ; 2 bytes
CP_M_SRC_P              = $0004 ; 2 bytes
CP_M_LEN                = $0006 ; 2 bytes
CONSOLE_CHARACTER_COUNT = $0008 ; 1 byte
SIMPLE_BUFFER_WRITE_PTR = $0009 ; 1 byte
SIMPLE_BUFFER_READ_PTR  = $000A ; 1 byte 
KEYBOARD_DECODE_STATE   = $000B ; 1 byte
KEYBOARD_MODIFIER_STATE = $000C ; 1 byte
KEYBOARD_LATEST_META    = $000D ; 1 byte
KEYBOARD_LATEST_CODE    = $000E ; 1 byte

CONSOLE_TEXT            = $0200 ; CONSOLE_LENGTH (32) bytes
SIMPLE_BUFFER           = $0300 ; 256 bytes

  .org $2000
  jmp initialize_machine

  .include initialize_machine_v2.inc
  .include display_routines_8bit.inc
  .include convert_to_hex.inc
  .include full_screen_console.inc
  .include simple_buffer.inc
  .include copy_memory.inc
  .include key_codes.inc

kb_seq_pause       .byte $e1, $14, $77, $e1, $f0, $14, $f0, $77, $00

kb_normal_from:    .byte $14, $11, $77, $7c, $7b, $79, $76, $05, $06, $04, $0c, $03, $0b, $83, $0a
                   .byte $01, $09, $78, $07, $7e, $5d, $58, $84, $00
kb_normal_to:      .byte $11, $19, $76, $7e, $84, $7c, $08, $07, $0f, $17, $1f, $27, $2f, $37, $3f
                   .byte $47, $4f, $56, $5e, $5f, $5c, $14, $57

kb_extended_from:  .byte $11, $14, $70, $71, $6b, $6c, $69, $75, $72, $7d, $7a, $74, $4a, $5a
                   .byte $1f, $27, $2f, $7e, $3f, $37, $5e, $7c, $00
kb_extended_to:    .byte $39, $58, $67, $64, $61, $6e, $65, $63, $60, $6f, $6d, $6a, $77, $79
                   .byte $8b, $8c, $8d, $62, $7f, $00, $00, $57

kb_modifier_codes: .byte KB_CODE_L_SHIFT, KB_CODE_R_SHIFT, KB_CODE_L_CTRL, KB_CODE_R_CTRL
                   .byte KB_CODE_L_ALT,   KB_CODE_R_ALT,   KB_CODE_L_GUI,  KB_CODE_R_GUI, $00
kb_modifier_masks: .byte KB_MOD_L_SHIFT,  KB_MOD_R_SHIFT,  KB_MOD_L_CTRL,  KB_MOD_R_CTRL
                   .byte KB_MOD_L_ALT,    KB_MOD_R_ALT,    KB_MOD_L_GUI,   KB_MOD_R_GUI

kb_modifier_from:  .byte (KB_MOD_L_SHIFT | KB_MOD_R_SHIFT), (KB_MOD_L_CTRL | KB_MOD_R_CTRL)
                   .byte (KB_MOD_L_ALT   | KB_MOD_R_ALT),   (KB_MOD_L_GUI  | KB_MOD_R_GUI), $00
kb_modifier_to     .byte KB_META_SHIFT,                     KB_META_CTRL
                   .byte KB_META_ALT,                       KB_META_GUI

program_start:
  sei

  ldx #$ff ; Initialize stack
  txs

  jsr reset_and_enable_display_no_cursor
  jsr console_initialize
  jsr simple_buffer_initialize

  ; relocate the interrupt handler
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

  ; Initialize Keyboard decode state
  stz KEYBOARD_DECODE_STATE
  stz KEYBOARD_MODIFIER_STATE

  lda #%00000110  ; CA2 independent interrupt rising edge
  sta PCR

  lda #%10000001  ; Enable CA2 interrupt
  sta IER

  cli

  jmp decode_loop

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
  lda KEYBOARD_LATEST_CODE
  jsr keyboard_translate_code
  cmp #0
  bne decode_loop_show_translation
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


; On entry A contains the byte from the keyboard
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
  bne keyboard_get_press_repeat ; It's a keyboard break code so keep reading
  ; Found a make code
  lda KEYBOARD_LATEST_CODE
  clc
keyboard_get_press_done:
  rts


; On entry A contains the byte from the keyboard
; On exit Carry set if no result so far
;         KEYBOARD_LATEST_META contains metadata for latest key event
;         KEYBOARD_LATEST_CODE contains code for latest key event
keyboard_set3_decode:
  jsr keyboard_decode
  bcs keyboard_set3_decode_done
  phx
  ldx #$ff                    ; Will be incremented at top of loop so loop starts at 0
  lda KEYBOARD_LATEST_META
  bit #KB_META_EXTENDED
  bne keyboard_set3_decode_extended
keyboard_set3_translate_normal:
  inx
  lda kb_normal_from, X
  beq keyboard_set3_translate_done
  cmp KEYBOARD_LATEST_CODE
  bne keyboard_set3_translate_normal
  ; Code found
  lda kb_normal_to, X
  sta KEYBOARD_LATEST_CODE
  bra keyboard_set3_translate_done
keyboard_set3_decode_extended:
  and #~KB_META_EXTENDED
  sta KEYBOARD_LATEST_META
keyboard_set3_translate_extended:
  inx
  lda kb_extended_from, X
  beq keyboard_set3_translate_done
  cmp KEYBOARD_LATEST_CODE
  bne keyboard_set3_translate_extended
  ; Code found
  lda kb_extended_to, X
  sta KEYBOARD_LATEST_CODE
  ; Fall through
keyboard_set3_translate_done:
  jsr keyboard_set3_modifier_track
  jsr keyboard_update_modifiers
  clc
  plx
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


; On entry KEYBOARD_MODIFIER_STATE containts the current state of modifiers
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


; On entry A contains the byte from the keyboard
; On exit Carry set if no result so far
;         KEYBOARD_LATEST_META contains metadata for latest key event
;         KEYBOARD_LATEST_CODE contains code for latest key event
keyboard_decode:
  phx
  tax                         ; X <- latest byte from keyboard
  lda KEYBOARD_DECODE_STATE
  bit #KB_DECODE_PAUSE
  bne kb_state_pause
  bit #KB_DECODE_BREAK
  bne kb_state_break
  bit #KB_DECODE_EXTENDED
  bne kb_state_extended
  ; fall through
kb_state_waiting:
  cpx #KB_CODE_BREAK
  beq kb_to_break
  cpx #KB_CODE_EXTENDED
  beq kb_to_extended
  cpx kb_seq_pause
  beq kb_to_pause
  lda #0
  bra kb_decode_emit

kb_state_pause:
  lda KEYBOARD_DECODE_STATE
  and #KB_DECODE_SEQUENCE
  phx
  tax                          ; X <- index of current code in sequence
  pla                          ; A <- latest byte from keyboard
  cmp kb_seq_pause, X
  bne kb_pause_error
  inx
  lda kb_seq_pause, X
  beq kb_pause_emit
  txa
  ora #KB_DECODE_PAUSE
  bra kb_decode_no_emit
kb_pause_emit:
  lda #0
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
  lda #KB_META_BREAK
  bra kb_decode_emit

kb_state_extended:
  cpx #KB_CODE_BREAK
  beq kb_to_extended_break
  lda #KB_META_EXTENDED
  cpx #KB_CODE_EXTENDED_IGNORE
  bne kb_decode_emit
  lda #0
  bra kb_decode_no_emit

kb_state_extended_break:
  lda #(KB_META_BREAK | KB_META_EXTENDED)
  cpx #KB_CODE_EXTENDED_IGNORE
  bne kb_decode_emit
  lda #0
  bra kb_decode_no_emit

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
  lda #(KB_DECODE_PAUSE | %00000001)
  bra kb_decode_no_emit

; A = Metadata
; X = code
kb_decode_emit:
  sta KEYBOARD_LATEST_META
  stx KEYBOARD_LATEST_CODE
  stz KEYBOARD_DECODE_STATE
  clc
  bra kb_decode_done

; A = new decode state
kb_decode_no_emit:
  sta KEYBOARD_DECODE_STATE
  sec
  ; Fall through

kb_decode_done:
  plx
  rts


; On entry A contains the keyboard code
; On exit  A contains the translated code or 0 if no translation available
;          X, Y are preserved
keyboard_translate_code:
  phx
  tax
  cpx #(key_codes_end - key_codes)
  bcs keyboard_translate_no_match
  lda key_codes, X
  bra keyboard_translate_code_done
keyboard_translate_no_match:
  lda #0
keyboard_translate_code_done:
  plx
  rts


; On entry A = byte to print to console in hex
; On exit X, Y are preserved
;         A is not preserved
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


interrupt:
  pha
  phx

  lda #%00000001  ; Clear the CA2 interrupt
  sta IFR

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

  plx
  pla
  rti
interrupt_end:
