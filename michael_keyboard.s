  .include base_config_v2.inc

INTERRUPT_ROUTINE       = $3f00

KB_DECODE_BREAK         = %10000000
KB_DECODE_EXTENDED      = %01000000
KB_DECODE_PAUSE         = %00100000
KB_DECODE_PRT_SCR       = %00010000
KB_DECODE_SEQUENCE      = %00000111

KB_CODE_BREAK           = 0xf0
KB_CODE_EXTENDED        = 0xe0

KB_META_BREAK           = %00000010
KB_META_EXTENDED        = %00000001

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
  tax       ; Store byte from keyboard into X register
  lda KEYBOARD_DECODE_STATE
  bit #KB_DECODE_PAUSE
  bne kb_state_pause
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
  ; TODO check for start of pause sequence
  stz KEYBOARD_LATEST_META
  stx KEYBOARD_LATEST_CODE
  stz KEYBOARD_DECODE_STATE
  clc
  jmp kb_decode_done

kb_state_pause:
  jmp kb_todo ; TODO

kb_state_prt_scr:
  bit #KB_DECODE_BREAK
  bne kb_state_prt_scr_break
  ; fall through
kb_state_prt_scr_make:
  jmp kb_todo ; TODO

kb_state_prt_scr_break:
  jmp kb_todo ; TODO

kb_state_break:
  bit #KB_DECODE_EXTENDED
  bne kb_state_extended_break
  lda #KB_META_BREAK
  sta KEYBOARD_LATEST_META
  stx KEYBOARD_LATEST_CODE
  stz KEYBOARD_DECODE_STATE
  clc
  jmp kb_decode_done

kb_state_extended:
  cpx #KB_CODE_BREAK
  beq kb_to_extended_break
  ; TODO check for start of print screen make sequence
  lda #KB_META_EXTENDED
  sta KEYBOARD_LATEST_META
  stx KEYBOARD_LATEST_CODE
  stz KEYBOARD_DECODE_STATE
  clc
  jmp kb_decode_done

kb_state_extended_break:
  ; TODO check for start of print screen break sequence
  lda #(KB_META_BREAK | KB_META_EXTENDED)
  sta KEYBOARD_LATEST_META
  stx KEYBOARD_LATEST_CODE
  stz KEYBOARD_DECODE_STATE
  clc
  jmp kb_decode_done

kb_to_break:
  lda #KB_DECODE_BREAK
  sta KEYBOARD_DECODE_STATE
  sec
  jmp kb_decode_done

kb_to_extended:
  lda #KB_DECODE_EXTENDED
  sta KEYBOARD_DECODE_STATE
  sec
  jmp kb_decode_done

kb_to_extended_break:
  lda #(KB_DECODE_EXTENDED | KB_DECODE_BREAK)
  sta KEYBOARD_DECODE_STATE
  sec
  jmp kb_decode_done

kb_todo:
  lda #"X"
  jsr console_print_character
  jsr console_show
kb_todo_loop:
  bra kb_todo_loop

kb_decode_done:
  plx
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

message:
  .asciiz "Value: "
