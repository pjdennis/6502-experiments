  .include base_config_v2.inc

INTERRUPT_ROUTINE       = $3f00

KB_DECODE_BREAK         = %10000000
KB_DECODE_EXTENDED      = %01000000
KB_DECODE_PAUSE         = %00100000
KB_DECODE_PRT_SCR       = %00010000
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
KB_CODE_REPEAT_PRT_SCR  = $7c
KB_CODE_PAUSE           = $62
KB_CODE_PRT_SCR         = $57

KB_META_BREAK           = %00000001
KB_META_EXTENDED        = %00000010

DISPLAY_STRING_PARAM    = $0000 ; 2 bytes
CP_M_DEST_P             = $0002 ; 2 bytes
CP_M_SRC_P              = $0004 ; 2 bytes
CP_M_LEN                = $0006 ; 2 bytes
CONSOLE_CHARACTER_COUNT = $0007 ; 1 byte
SIMPLE_BUFFER_WRITE_PTR = $0008 ; 1 byte
SIMPLE_BUFFER_READ_PTR  = $0009 ; 1 byte 
KEYBOARD_DECODE_STATE   = $000A ; 1 byte
KEYBOARD_MODIFIER_STATE = $000B ; 1 byte
KEYBOARD_LATEST_META    = $000C ; 1 byte
KEYBOARD_LATEST_CODE    = $000D ; 1 byte
KEYBOARD_SCRATCH        = $000E ; 1 byte

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

KB_SEQ_OFFSET_CODE  = 0
KB_SEQ_OFFSET_COUNT = 1
KB_SEQ_OFFSET_SEQ   = 2

kb_seq_start:
;                           Code         Count  Sequence
kb_seq_pause_make:    .byte KB_CODE_PAUSE,   8, $e1, $14, $77, $e1, $f0, $14, $f0, $77
kb_seq_prt_scr_make:  .byte KB_CODE_PRT_SCR, 3, $12, $e0, $7c
kb_seq_prt_scr_break: .byte KB_CODE_PRT_SCR, 4, $7c, $e0, $f0, $12

kb_normal_from:   .byte $14, $11, $77, $7c, $7b, $79, $76, $05, $06, $04, $0c, $03, $0b, $83, $0a
                  .byte $01, $09, $78, $07, $7e, $5d, $00

kb_normal_to:     .byte $11, $19, $76, $7e, $84, $7c, $08, $07, $0f, $17, $1f, $27, $2f, $37, $3f
                  .byte $47, $4f, $56, $5e, $5f, $5c

kb_extended_from: .byte $11, $14, $70, $71, $6b, $6c, $69, $75, $72, $7d, $7a, $74, $4a, $5a, $00

kb_extended_to:   .byte $39, $58, $67, $64, $61, $6e, $65, $63, $60, $6f, $6d, $6a, $77, $79

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

decode_loop:
  jsr simple_buffer_read
  bcs decode_loop               ; If no byte available jump back to read again
  jsr keyboard_set3_decode
  bcs decode_loop               ; If nothing yet decoded jump back to read again
decode_loop_2:
  lda KEYBOARD_LATEST_META
  jsr console_print_hex
  lda KEYBOARD_LATEST_CODE
  jsr console_print_hex
  jsr simple_buffer_read
  bcs decode_show               ; If no byte available jump to show what we have
  jsr keyboard_set3_decode
  bcc decode_loop_2             ; If something decoded jump back to show it
  ; Fall through
decode_show:
  jsr console_show
  bra decode_loop


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
  clc
  plx
keyboard_set3_decode_done:
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
  bne kb_state_pause_make
  bit #KB_DECODE_PRT_SCR
  bne kb_state_prt_scr
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
  cpx kb_seq_pause_make + KB_SEQ_OFFSET_SEQ
  beq kb_to_pause_make
  lda #0
  bra kb_decode_emit

kb_state_pause_make:
  lda #(kb_seq_pause_make - kb_seq_start)
  bra kb_seq_check

kb_state_prt_scr:
  bit #KB_DECODE_BREAK
  bne kb_state_prt_scr_break
  ; fall through
kb_state_prt_scr_make:
  lda #(kb_seq_prt_scr_make - kb_seq_start)
  bra kb_seq_check

kb_state_prt_scr_break:
  lda #(kb_seq_prt_scr_break - kb_seq_start)
  bra kb_seq_check

kb_state_break:
  bit #KB_DECODE_EXTENDED
  bne kb_state_extended_break
  lda #KB_META_BREAK
  bra kb_decode_emit

kb_state_extended:
  cpx #KB_CODE_BREAK
  beq kb_to_extended_break
  cpx kb_seq_prt_scr_make + KB_SEQ_OFFSET_SEQ
  beq kb_to_prt_scr_make
  lda #KB_META_EXTENDED
  ; Repeating print screen does not repeat the full sequence
  cpx #KB_CODE_REPEAT_PRT_SCR
  bne kb_decode_emit
  lda #0
  ldx kb_seq_prt_scr_make + KB_SEQ_OFFSET_CODE
  bra kb_decode_emit

kb_state_extended_break:
  cpx kb_seq_prt_scr_break + KB_SEQ_OFFSET_SEQ
  beq kb_to_prt_scr_break
  lda #(KB_META_BREAK | KB_META_EXTENDED)
  bra kb_decode_emit

kb_to_break:
  lda #KB_DECODE_BREAK
  bra kb_decode_no_emit

kb_to_extended:
  lda #KB_DECODE_EXTENDED
  bra kb_decode_no_emit

kb_to_extended_break:
  lda #(KB_DECODE_EXTENDED | KB_DECODE_BREAK)
  bra kb_decode_no_emit

kb_to_pause_make:
  lda #(KB_DECODE_PAUSE | %00000001)
  bra kb_decode_no_emit

kb_to_prt_scr_make:
  lda #(KB_DECODE_EXTENDED | KB_DECODE_PRT_SCR | %00000001)
  bra kb_decode_no_emit

kb_to_prt_scr_break:
  lda #(KB_DECODE_EXTENDED | KB_DECODE_BREAK | KB_DECODE_PRT_SCR | %00000001)
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

; X = latest byte from keyboard
; A = offset to start of sequence data
kb_seq_check:
  sta KEYBOARD_SCRATCH        ; KEYBOARD_SCRATCH <- offset to start of sequence data

  ; Check latest byte against expected
  lda KEYBOARD_DECODE_STATE
  and #KB_DECODE_SEQUENCE
  clc
  adc KEYBOARD_SCRATCH
  phx
  tax                         ; X <- offset to byte we should check against
  pla                         ; A <- latest byte from keyboard
  cmp kb_seq_start + KB_SEQ_OFFSET_SEQ, X
  bne kb_seq_error            ; If latest byte not matching expected then bail out - error  

  ; If it was the last in sequence emit the code
  ldx KEYBOARD_SCRATCH        ; X <- offset to sequence data
  lda KEYBOARD_DECODE_STATE
  and #KB_DECODE_SEQUENCE
  inc
  cmp kb_seq_start + KB_SEQ_OFFSET_COUNT, X
  beq kb_seq_emit             ; Emit the code

  ; Otherwise update state to reflect next count and exit without emitting
  sta KEYBOARD_SCRATCH        ; KEYBOARD_SCRATCH <- New sequence count
  lda KEYBOARD_DECODE_STATE
  and #~KB_DECODE_SEQUENCE
  ora KEYBOARD_SCRATCH
  bra kb_decode_no_emit

; A = latest byte from keyboard
kb_seq_error:
  ; Reset state and reprocess with the current code
  tax
  lda #0
  sta KEYBOARD_DECODE_STATE
  jmp kb_state_waiting

; X = offset to sequence data
kb_seq_emit:
  ; Retrieve the code
  lda kb_seq_start + KB_SEQ_OFFSET_CODE, X
  tax
  ; Retrieve the metadata
  lda KEYBOARD_DECODE_STATE
  bit #KB_DECODE_BREAK
  bne kb_seq_emit_break
  lda #0
  bra kb_decode_emit
kb_seq_emit_break:
  lda #KB_META_BREAK
  bra kb_decode_emit


; TODO no longer used
kb_todo:
  lda #"X"
  jsr console_print_character
  jsr console_show
kb_todo_loop:
  bra kb_todo_loop


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

message:
  .asciiz "Value: "
