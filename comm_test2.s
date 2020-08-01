PORTB = $6000
PORTA = $6001
DDRB  = $6002
DDRA  = $6003

; PORTA assignments
BANK_MASK         = %00001111
ILED              = %00010000
LED               = %00100000
BUTTON1           = %01000000
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

; Shared ram locations
DOWN_TIMES          = $2100
UP_TIMES            = $2200

  .org $8000

  ; Place code for delay_routines at start of page to ensure no page boundary crossings during timing loops
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

  ; Configure shift clock time
  lda #104               ; 2 ; 2 MHz / 9600 bps / 2
  sta T2CL               ; 3

  lda #ACR_SR_IN_T2      ; 2 Shift in under control of T2
  sta ACR                ; 4

  ; Configure CB2 for independent interrupt - negative edge
  lda #PCR_CB2_IND_POS_E
  sta PCR

  lda #(IERSETCLEAR | ICB2 | ISR) ; Enable CB2 and SR interrupts
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
  lda #200
  jsr delay_10_thousandths

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  ldx #0
display_down:
  lda DOWN_TIMES, X
  jsr display_hex
  inx
  cpx #8
  bne display_down
  lda #200
  jsr delay_10_thousandths

  bra display_loop


; Interrupt handler - switch memory banks and routines
interrupt:               ; 6?
  pha                    ; 3

  lda IFR                ; 4
  and #ICB2              ; 2
  beq check_for_shift_complete ; 2 (not taken)

  lda #ICB2              ; 2 Disable the interrupt
  sta IER                ; 4
  stz PCR                ; 4 Clear CB2 control

  stz SR                 ; 4 Start the shifting; maybe we are ~ 52 cycles in to the ISR? 

  lda #ILED              ; 2  Turn on interrupt activity LED
  tsb PORTA
  nop
  nop
  nop
  nop
  nop
  nop

  bra interrupt_done

check_for_shift_complete:
  lda #ILED              ; 2  Turn on interrupt activity LED
  tsb PORTA
  
  lda IFR
  and #ISR
  beq interrupt_done

  lda #$77
  sta DOWN_TIMES

  phx
  phy

  ldy SR

  lda #0                 ; Turn off shifting
  sta ACR

  lda #ICB2
  sta IFR
  lda #ISR
  sta IER
;  lda #(IERSETCLEAR | ICB2) ; Enable CB2 interrupts
;  sta IER

  ldx #0
move1:
  lda UP_TIMES + 1, X
  sta UP_TIMES, X
  inx
  cpx #7
  bne move1

  sty UP_TIMES + 7

  ply
  plx

interrupt_done:
  lda #ILED              ; Turn off interrupt activity LED
  trb PORTA

  pla
  rti                    ; Return to the program in the incoming bank


; Vectors
  .org $fffc
  .word reset
  .word interrupt
