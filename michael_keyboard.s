  .include base_config_v2.inc

INTERRUPT_ROUTINE       = $3f00

KB_DECODE_BREAK         = %10000000
KB_DECODE_EXTENDED      = %01000000
KB_DECODE_PAUSE         = %00100000
KB_DECODE_PRT_SCR       = %00010000
KB_DECODE_SEQUENCE      = %00000111

KB_CODE_BREAK           = 0xf0
KB_CODE_EXTENDED        = 0xe0
KB_CODE_REPEAT_PRT_SCR  = 0x7c
KB_CODE_PAUSE           = 0x62
KB_CODE_PRT_SCR         = 0x57

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
KEYBOARD_LATEST_META    = $000B ; 1 byte
KEYBOARD_LATEST_CODE    = $000C ; 1 byte
KEYBOARD_SCRATCH        = $000D ; 1 byte

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
kb_seq_pause_make:    .byte KB_CODE_PAUSE,   8, 0xe1, 0x14, 0x77, 0xe1, 0xf0, 0x14, 0xf0, 0x77
kb_seq_prt_scr_make:  .byte KB_CODE_PRT_SCR, 3, 0x12, 0xe0, 0x7c
kb_seq_prt_scr_break: .byte KB_CODE_PRT_SCR, 4, 0x7c, 0xe0, 0xf0, 0x12

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

  lda #%00000110  ; CA2 independent interrupt rising edge
  sta PCR

  lda #%10000001  ; Enable CA2 interrupt
  sta IER

  cli

decode_loop:
  jsr simple_buffer_read
  bcs decode_loop               ; If no byte available jump back to read again
  jsr keyboard_decode
  bcs decode_loop               ; If nothing yet decoded jump back to read again
decode_loop_2:
  lda KEYBOARD_LATEST_META
  jsr console_print_hex
  lda KEYBOARD_LATEST_CODE
  jsr console_print_hex
  jsr simple_buffer_read
  bcs decode_show               ; If no byte available jump to show what we have
  jsr keyboard_decode
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
  jmp kb_decode_emit

kb_state_pause_make:
  lda #(kb_seq_pause_make - kb_seq_start)
  jmp kb_seq_check

kb_state_prt_scr:
  bit #KB_DECODE_BREAK
  bne kb_state_prt_scr_break
  ; fall through
kb_state_prt_scr_make:
  lda #(kb_seq_prt_scr_make - kb_seq_start)
  jmp kb_seq_check

kb_state_prt_scr_break:
  lda #(kb_seq_prt_scr_break - kb_seq_start)
  jmp kb_seq_check

kb_state_break:
  bit #KB_DECODE_EXTENDED
  bne kb_state_extended_break
  lda #KB_META_BREAK
  jmp kb_decode_emit

kb_state_extended:
  cpx #KB_CODE_BREAK
  beq kb_to_extended_break
  cpx kb_seq_prt_scr_make + KB_SEQ_OFFSET_SEQ
  beq kb_to_prt_scr_make
  lda #KB_META_EXTENDED
  ; Repeating print screen does not repeat the full sequence
  cpx #KB_CODE_REPEAT_PRT_SCR
  bne kb_state_extended_store_result
  lda #0
  ldx kb_seq_prt_scr_make + KB_SEQ_OFFSET_CODE
kb_state_extended_store_result:
  jmp kb_decode_emit

kb_state_extended_break:
  cpx kb_seq_prt_scr_break + KB_SEQ_OFFSET_SEQ
  beq kb_to_prt_scr_break
  lda #(KB_META_BREAK | KB_META_EXTENDED)
  jmp kb_decode_emit

kb_to_break:
  lda #KB_DECODE_BREAK
  jmp kb_decode_no_emit

kb_to_extended:
  lda #KB_DECODE_EXTENDED
  jmp kb_decode_no_emit

kb_to_extended_break:
  lda #(KB_DECODE_EXTENDED | KB_DECODE_BREAK)
  jmp kb_decode_no_emit

kb_to_pause_make:
  lda #(KB_DECODE_PAUSE | %00000001)
  jmp kb_decode_no_emit

kb_to_prt_scr_make:
  lda #(KB_DECODE_EXTENDED | KB_DECODE_PRT_SCR | %00000001)
  jmp kb_decode_no_emit

kb_to_prt_scr_break:
  lda #(KB_DECODE_EXTENDED | KB_DECODE_BREAK | KB_DECODE_PRT_SCR | %00000001)
  jmp kb_decode_no_emit

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
  jmp kb_decode_no_emit

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
  jmp kb_decode_emit
kb_seq_emit_break:
  lda #KB_META_BREAK
  jmp kb_decode_emit

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
