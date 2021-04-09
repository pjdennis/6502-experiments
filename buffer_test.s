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
BUFFER_WRITE_PTR        = $0003 ; 1 byte
BUFFER_READ_PTR         = $0004 ; 1 byte
VALUE_COUNTER           = $0005 ; 1 byte

CONSOLE_TEXT            = $0200
BUFFER                  = $0300

  .org $2000
  jmp program_entry

  ; Place delay_routines at start of page to ensure no page boundary crossings during timing loops
  .include delay_routines.inc

  ; Additional routines
  .include display_routines.inc
  .include display_string.inc
  .include full_screen_console.inc

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

  stz VALUE_COUNTER

  lda #PCR_CA2_IND_NEG_E
  sta PCR
  lda #(IERSETCLEAR | ICA2)
  sta IER
  cli



  ldx #0
show_hex_loop:
  txa
  jsr console_print_hex
  jsr console_show
  lda #50
  jsr delay_hundredths
  inx
  bra show_hex_loop
  

show_restart:
  ldx #'A'
show_loop:
  txa
  jsr console_print_character
  jsr console_show
  lda #50
  jsr delay_hundredths
  inx
  cpx #('Z' + 1)
  bne show_loop
  bra show_restart


buffer_initialize:
  stz BUFFER_WRITE_PTR
  stz BUFFER_READ_PTR

; On entry A = byte to write
; On exit A, X, Y are preserved
;         C = Set if buffer full
buffer_write:
  phx
  ldx BUFFER_WRITE_PTR
  inx
  cpx BUFFER_READ_PTR
  beq buffer_write_full
  sta BUFFER, X
  stx BUFFER_WRITE_PTR
  clc
  bra buffer_write_done
buffer_write_full:
  sec
buffer_write_done:
  plx
  rts


; On exit A = value from buffer
;         C = Set if buffer is empty
;         X, Y are preserved
buffer_read:
  phx
  ldx BUFFER_READ_PTR
  cpx BUFFER_WRITE_PTR
  beq buffer_read_empty
  lda BUFFER, X
  inx
  stx BUFFER_READ_PTR
  clc
  bra buffer_read_done
buffer_read_empty:
  sec  
buffer_read_done:
  plx
  rts 


; Interrupt handler - switch memory banks and routines
interrupt:
  pha
  lda #ICA2
  sta IFR

  inc VALUE_COUNTER

  pla
  rti
