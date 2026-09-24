PORTB = $6000
PORTA = $6001
DDRB  = $6002
DDRA  = $6003

; PORTA assignments
BANK_MASK         = %00001111
ILED              = %00010000
LED               = %00100000
FLASH_LED         = %01000000
SERIAL_IN         = %10000000

BANK_START        = %00000100
BANK_STOP         = %00010000

; PORTB assignments
T1_SQWAVE_OUT     = %10000000
DISPLAY_DATA_MASK = %01111000
E                 = %00000100
RW                = %00000010
RS                = %00000001

BF                = %01000000
DISPLAY_BITS_MASK = (DISPLAY_DATA_MASK | E | RW | RS)

; Include additional definitions
  .include display_parameters.inc
  .include 6522.inc


BIT_TIMER_INTERVAL      = 208 - 1 ; 2 MHz / 9600 bps   ; 2 byte counter
;BIT_TIMER_INTERVAL      = 52 - 1  ; 2 MHz / 38400 bps
;BIT_TIMER_INTERVAL      = 69 - 1  ; 4 MHz / 57600 bps
;BIT_TIMER_INTERVAL      = 104 - 1 ; 4 MHz / 38400 bps
;BIT_TIMER_INTERVAL      = 52 - 1  ; 1 MHz / 19200 bps
;BIT_TIMER_INTERVAL      = 104     ; 1 MHz / 9600 bps
;BIT_TIMER_INTERVAL      = 208     ; 1 MHz / 4800 bps
;BIT_TIMER_INTERVAL      = 3333    ; 1 MHz / 300 bps
ICB2_TO_T1_START         = 19
IT1_TO_READ              = 20

;FIRST_BIT_TIMER_INTERVAL = BIT_TIMER_INTERVAL * 1.33 - ICB2_TO_T1_START - IT1_TO_READ
FIRST_BIT_TIMER_INTERVAL = BIT_TIMER_INTERVAL * 1.5 - ICB2_TO_T1_START - IT1_TO_READ


; Shared ram locations
RECEIVE_COUNTER     = $00 ; 2 bytes

  .org $8000

  ; Place code for delay_routines at start of page to ensure no page boundary crossings
  ; during timing loops
  .include delay_routines.inc

  .include display_routines.inc
  .include convert_to_hex.inc

reset:
  ldx #$ff ; Initialize stack
  txs

  lda #0   ; Initialize status flags
  pha
  plp

  ; Initialize 6522 port A (memory banking control)
  lda #BANK_START
  sta PORTA
  lda #(BANK_MASK | LED | ILED | FLASH_LED) ; Set pin direction  on port A
  sta DDRA

  ; Initialize 6522 port B (display control)
  lda #0
  sta PORTB
  lda #(DISPLAY_BITS_MASK | T1_SQWAVE_OUT) ; Set display pins and T1 output pins to output
  sta DDRB

  ; Initialize display
  jsr reset_and_enable_display_no_cursor


  stz RECEIVE_COUNTER
  stz RECEIVE_COUNTER + 1

  ; Configure CB2 for independent interrupt; Negative edge because we're not inverting
  ; the incoming serial receive line to adapt voltage levels
  lda #PCR_CB2_IND_NEG_E
  sta PCR

  lda #(IERSETCLEAR | ICB2) ; Enable CB2 interrupts
  sta IER

display_loop:
  lda #DISPLAY_SECOND_LINE ; Display the second line - counter and ASCII characters
  jsr move_cursor

  lda RECEIVE_COUNTER + 1
  jsr display_hex
  lda RECEIVE_COUNTER
  jsr display_hex

  bra display_loop


  .org $ff00                     ; Place in it's own page to avoid extra cycles during branch

; Interrupt handler - Read in serial data
interrupt:                       ; 7 cycles to get into the handler
  pha                            ; 3

  lda #ILED                      ; Turn on interrupt activity LED
  tsb PORTA

  ; We assume this is a cb2 interrupt
  inc RECEIVE_COUNTER
  bne counter_incremented
  inc RECEIVE_COUNTER + 1
counter_incremented:

  lda #ICB2                      ; Clear the cb2 interrupt flag
  sta IFR                        ; 4

  lda #ILED                      ; Turn off interrupt activity LED
  trb PORTA

  pla                            ; 4
  rti                            ; 6 Return to the program in the incoming bank


; Vectors
  .org $fffc
  .word reset
  .word interrupt
