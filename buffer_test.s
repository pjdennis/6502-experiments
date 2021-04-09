  .include base_config_v1.inc

; PORTA assignments
MORSE_LED         = %00010000
CONTROL_BUTTON    = %00100000
CONTROL_LED       = %01000000
SD_CSB            = %10000000

PORTA_OUT_MASK    = BANK_MASK | CONTROL_LED | MORSE_LED | SD_CSB

SD_DATA           = %00001000
SD_CLK            = %00010000
SD_DC             = %00100000
SD_CS_PORT        = PORTA
SD_DATA_PORT      = PORTB

; PORTB assignments
T1_SQWAVE_OUT     = %10000000

PORTB_OUT_MASK    = DISPLAY_BITS_MASK | T1_SQWAVE_OUT

; Variables
DISPLAY_STRING_PARAM    = $0000 ; 2 bytes
CONSOLE_CHARACTER_COUNT = $0002 ; 1 byte
SIMPLE_BUFFER_WRITE_PTR = $0003 ; 1 byte
SIMPLE_BUFFER_READ_PTR  = $0004 ; 1 byte
VALUE_COUNTER           = $0005 ; 1 byte

CONSOLE_TEXT            = $0200
SIMPLE_BUFFER           = $0300

  .org $2000
  jmp program_entry

  ; Place delay_routines at start of page to ensure no page boundary crossings during timing loops
  .include delay_routines.inc

  ; Additional routines
  .include display_routines.inc
  .include display_string.inc
  .include full_screen_console.inc
  .include simple_buffer.inc
  .include convert_to_hex.inc

program_entry:
  ldx #$ff                                 ; Initialize stack
  txs

  lda #0                                   ; Initialize status flags
  pha
  plp

  ; Initialize 6522 port A (memory banking control)
  lda #(BANK_START | SD_CSB)
  sta PORTA
  lda #PORTA_OUT_MASK                      ; Set pin direction on port A
  sta DDRA

  ; Initialize 6522 port B (display control)
  lda #0
  sta PORTB
  lda #PORTB_OUT_MASK                      ; Set pin direction on port B
  sta DDRB

  ; Set up the RAM vector pull location
  lda #<interrupt
  sta $3ffe
  lda #>interrupt
  sta $3fff

  ; Initialize display
  jsr reset_and_enable_display_no_cursor

  jsr console_initialize
  jsr simple_buffer_initialize
  stz VALUE_COUNTER

  lda #PCR_CA2_IND_NEG_E
  sta PCR
  lda #(IERSETCLEAR | ICA2)
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


; Interrupt handler - switch memory banks and routines
interrupt:
  pha
  lda #ICA2
  sta IFR

  lda VALUE_COUNTER
  jsr simple_buffer_write
  inc VALUE_COUNTER

  pla
  rti
