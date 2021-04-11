  .include base_config_v2.inc

INTERRUPT_ROUTINE       = $3f00

DISPLAY_STRING_PARAM    = $0000 ; 2 bytes
CP_M_DEST_P             = $0002 ; 2 bytes
CP_M_SRC_P              = $0004 ; 2 bytes
CP_M_LEN                = $0006 ; 2 bytes
CONSOLE_CHARACTER_COUNT = $0007 ; 1 byte
SIMPLE_BUFFER_WRITE_PTR = $0008 ; 1 byte
SIMPLE_BUFFER_READ_PTR  = $0009 ; 1 byte 

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

  lda #%00000110  ; CA2 independent interrupt rising edge
  sta PCR

  lda #%10000001  ; Enable CA2 interrupt
  sta IER

  cli

show_simple_buffer_loop:
  jsr simple_buffer_read
  bcs show_simple_buffer_loop
show_simple_buffer_copy_loop:
  jsr convert_to_hex
  jsr console_print_character
  txa
  jsr console_print_character
  jsr simple_buffer_read
  bcc show_simple_buffer_copy_loop
  jsr console_show
  bra show_simple_buffer_loop


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
