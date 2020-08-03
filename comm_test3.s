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


BIT_TIMER_INTERVAL       = 69 - 1  ; 4 MHz / 57600 bps
;BIT_TIMER_INTERVAL      = 104 - 1 ; 4 MHz / 38400 bps
;BIT_TIMER_INTERVAL      = 52 - 1  ; 1 MHz / 19200 bps
;BIT_TIMER_INTERVAL      = 104     ; 1 MHz / 9600 bps
;BIT_TIMER_INTERVAL      = 208     ; 1 MHz / 4800 bps
;BIT_TIMER_INTERVAL      = 3333    ; 1 MHz / 300 bps
ICB2_TO_T1_START         = 19
IT1_TO_READ              = 20

;FIRST_BIT_TIMER_INTERVAL = BIT_TIMER_INTERVAL * 1.33 - ICB2_TO_T1_START - IT1_TO_READ
FIRST_BIT_TIMER_INTERVAL = BIT_TIMER_INTERVAL * 1.5 - ICB2_TO_T1_START - IT1_TO_READ

NUMBER_OF_BITS           = 8    ; Not counting start or stop bits. There's no parity bit.
STATE_WAITING_FOR_CB2    = 0
STATE_WAITING_FOR_TIMER  = 1

; Shared ram locations
UP_TIMES_P          = $00 ; 2 bytes
BIT_VALUE           = $02
SERIAL_WAITING      = $03
DOWN_TIMES          = $2100
UP_TIMES            = $2200
DATA_BUFFER         = $2300

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


  ldx #8
clear_loop:
  dex
  stz UP_TIMES, X
  stz DOWN_TIMES, X
  bne clear_loop

  lda #<(UP_TIMES + 8)
  sta UP_TIMES_P
  lda #>(UP_TIMES + 8)
  sta UP_TIMES_P + 1

  ; Configure T1 continuous clock
  lda #ACR_T1_CONT
  sta ACR  

  ; Configure CB2 for independent interrupt; Positive edge because we're inverting
  ; the incoming serial receive line to adapt voltage levels
  lda #PCR_CB2_IND_POS_E
  sta PCR

  ; Initialize for serial receive
  lda #<FIRST_BIT_TIMER_INTERVAL ; Load timer duration to center of first bit
  sta T1CL

  lda #1
  sta SERIAL_WAITING

  lda #$80
  sta BIT_VALUE

  lda #(IERSETCLEAR | ICB2) ; Enable CB2 interrupts
  sta IER

  lda #(IERSETCLEAR | IT1)       ; Enable timer interrupts
  sta IER


display_loop:
  ldy #8                   ; Copy data to buffer in reverse order, ready for display
  lda UP_TIMES_P
  clc
  adc #($100 - 8)
  tax
copy_loop:
  lda UP_TIMES, X
  inx
  dey
  sta DATA_BUFFER, Y
  bne copy_loop

  lda #DISPLAY_FIRST_LINE  ; Display the first line
  jsr move_cursor
  ldx #8                   ; Display data that is in reverse order in DATA_BUFFER
display_up:
  dex
  lda DATA_BUFFER, X
  jsr display_hex
  cpx #0
  bne display_up

  lda #DISPLAY_SECOND_LINE ; Display the second line
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


  .org $ff00                     ; Place in it's own page to avoid extra cycles during branch

; Interrupt handler - Read in serial data
interrupt:                       ; 7 cycles to get into the handler
  pha                            ; 3

  lda SERIAL_WAITING             ; 3 (zero page)
  beq timer_interrupt            ; 2 (when not taken)


cb2_interrupt:
;  lda #>FIRST_BIT_TIMER_INTERVAL ; 2 Start the timer (low byte already in latch)
;  sta T1CH                       ; 4 (Starts at about 21 cycles in)
  stz T1CH                       ; 4 Assumes FIRST_BIT_TIMER_INTERVAL < 256 (19 cycles in)

  lda #<BIT_TIMER_INTERVAL       ; 2 Load bit-to-bit timer duration into latches
  sta T1LL                       ; 4
;  lda #>BIT_TIMER_INTERVAL       ; 2 ; Commenting this assumes FIRST_BIT_TIMER_INTERVAL < 256
;  sta T1LH                       ; 4

  lda #ICB2                      ; 2 Disable the CB2 interrupt
  sta IER                        ; 4

  stz SERIAL_WAITING             ; 3 (zero page)
 
  ; Dup of interrupt_done code
  pla                            ; 4
  rti                            ; 6 (About 25 cycles to get out)


timer_interrupt:
  lda PORTA                      ; 4 (read at 20 cycles in)
;  sec                            ; 2
;  and #SERIAL_IN                 ; 2
;  beq process_serial_bit         ; 3 (assuming taken) pin is low meaning a 1 came in on serial
;  clc                            ; 2 pin is high meaning a zero came in on serial
;process_serial_bit:
  rol                            ; 2 Assumes input pin is on bit 7

  ror BIT_VALUE                  ; 5 (zero page)

  lda #IT1                       ; 2 Clear the timer interrupt
  sta IFR                        ; 4

  bcs done_with_byte             ; 2 (when not taken)

  ; Dup of interrupt_done code
  pla                            ; 4
  rti                            ; 6 (About 25 cycles to get out)

done_with_byte:
  lda #ICB2                      ; 2 Clear CB2 interrupt
  sta IFR                        ; 4

; Stop timer 1 while keeping timer interrupts enabled
  stz ACR                        ; 4 Timer to 1 shot mode
  stz T1CL                       ; 4 Load a 0 into the timer; will expire after one cycleL
  stz T1CH                       ; 4

  lda BIT_VALUE                  ; 3 (zero page)
  sta (UP_TIMES_P)               ; 5 (indirect, zero page)
  inc UP_TIMES_P                 ; 5 (zero page)

; Reset serial state
  lda #<FIRST_BIT_TIMER_INTERVAL ; 2 Load timer duration to center of first bit
  sta T1CL                       ; 4

  lda #1                         ; 2
  sta SERIAL_WAITING             ; 4

  lda #$80                       ; 2
  sta BIT_VALUE                  ; 4

  lda #(IERSETCLEAR | ICB2)      ; 2 Renable CB2 interrupts
  sta IER                        ; 4

; TODO clear timer and CB2 interrupts in the same statement
  lda #IT1                       ; Clear the timer interrupt flag
  sta IFR                        ; 4

  ; Configure T1 continuous clock
  lda #ACR_T1_CONT
  sta ACR  

interrupt_done:
  pla                            ; 4
  rti                            ; 6 Return to the program in the incoming bank


; Vectors
  .org $fffc
  .word reset
  .word interrupt
