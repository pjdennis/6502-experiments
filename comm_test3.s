PORTB = $6000
PORTA = $6001
DDRB  = $6002
DDRA  = $6003

; PORTA assignments
BANK_MASK         = %00001111
ILED              = %00010000
LED               = %00100000
SERIAL_IN         = %01000000
FLASH_LED         = %10000000

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


BIT_TIMER_INTERVAL       = 3333 ; 1 MHz / 300 bps
NUMBER_OF_BITS           = 8    ; Not counting start or stop bits. There's no parity bit.
STATE_WAITING_FOR_CB2    = 0
STATE_WAITING_FOR_TIMER  = 1

; Shared ram locations
BIT_COUNT           = $2000
BIT_VALUE           = $2001
SERIAL_STATE        = $2002
DOWN_TIMES          = $2100
UP_TIMES            = $2200


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


  ldx #0
clear_loop:
  stz UP_TIMES, X
  stz DOWN_TIMES, X
  inx
  cpx #8
  bne clear_loop

  ; Configure T1 continuous clock
  lda #ACR_T1_CONT
  sta ACR  

  ; Load low byte timer interval into T1 latch
  lda #<BIT_TIMER_INTERVAL
  sta T1CL

  ; Configure CB2 for independent interrupt; Positive edge because we're inverting
  ; the incoming serial receive line to adapt voltage levels
  lda #PCR_CB2_IND_POS_E
  sta PCR

  ; Initialize for serial receive
  lda #NUMBER_OF_BITS
  sta BIT_COUNT

  lda #STATE_WAITING_FOR_CB2
  sta SERIAL_STATE

  stz BIT_VALUE

  lda #(IERSETCLEAR | ICB2) ; Enable CB2 interrupts
  sta IER


display_loop:
  lda #DISPLAY_FIRST_LINE
  jsr move_cursor
  ldx #0
display_up:
  lda UP_TIMES, X
  jsr display_hex
  inx
  cpx #8
  bne display_up

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  ldx #0
display_down:
  lda DOWN_TIMES, X
  jsr display_hex
  inx
  cpx #8
  bne display_down
  
  lda #100
  jsr delay_10_thousandths

  bra display_loop


; Interrupt handler - Read in serial data
interrupt:                      ; 7 cycles to get into the handler
  pha                           ; 3

  lda #ILED                     ; 2  Turn on interrupt activity LED
  tsb PORTA                     ; 4

  lda SERIAL_STATE              ; 4
  cmp #STATE_WAITING_FOR_TIMER  ; 2
  beq check_for_timer_interrupt ; 2 (when not taken)
  ; Only other option is STATE_WAITING_FOR_CB2 - fall through


check_for_cb2_interrupt:
  lda IFR                        ; 4
  and #ICB2                      ; 2
  beq error_unexpected_interrupt ; 2 (assuming not taken) 
; cb2 interrupt detected
  lda #>BIT_TIMER_INTERVAL       ; 4 Start the timer (low byte already in latch)
  sta T1CH                       ; 4 (Starts at about 40 cycles in)

  lda #(IERSETCLEAR | IT1)       ; Enable timer interrupts
  sta IER

  lda #IT1                       ; Clear timer interrupt
  sta IFR

  lda #ICB2                      ; Disable the CB2 interrupt
  sta IER

  lda #STATE_WAITING_FOR_TIMER
  sta SERIAL_STATE
 
  bra interrupt_done


check_for_timer_interrupt:
  lda IFR
  and #IT1
  beq error_unexpected_interrupt
; Timer interrupt detected
  lda PORTA
  sec
  and #SERIAL_IN
  beq process_serial_bit        ; pin is low meaning a 1 came in on serial
  clc                           ; pin is high meaning a zero came in on serial
process_serial_bit:
  ror BIT_VALUE

  lda #IT1                      ; Clear the timer interrupt
  sta IFR

  dec BIT_COUNT
  bne interrupt_done  

; Done with the byte
  lda #IT1                      ; Disable timer interrupts
  sta IER
 
  phx
  ldx #0
move1:
  lda UP_TIMES + 1, X
  sta UP_TIMES, X
  inx
  cpx #7
  bne move1
  plx

  lda BIT_VALUE
  sta UP_TIMES + 7

; Reset serial state
  lda #ICB2                     ; Clear CB2 interrupt
  sta IFR

  lda #NUMBER_OF_BITS
  sta BIT_COUNT

  lda #STATE_WAITING_FOR_CB2
  sta SERIAL_STATE

  stz BIT_VALUE

  lda #(IERSETCLEAR | ICB2)     ; Renable CB2 interrupts
  sta IER

  bra interrupt_done


error_unexpected_interrupt:


interrupt_done:
  lda #ILED              ; Turn off interrupt activity LED
  trb PORTA

  pla
  rti                    ; Return to the program in the incoming bank


; Vectors
  .org $fffc
  .word reset
  .word interrupt
