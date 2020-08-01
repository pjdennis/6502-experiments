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
BUTTON_DOWN_COUNTER = $2000
BUTTON_UP_COUNTER   = $2001

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


  stz BUTTON_DOWN_COUNTER
  stz BUTTON_UP_COUNTER

  ; Configure CA2 for independent interrupt - positive edge ...
  ;       and CB2 for independent interrupt - negative edge
  ;lda #(PCR_CA2_IND_POS_E | PCR_CB2_IND_NEG_E)
  lda #PCR_CB2_IND_POS_E
  ;lda #PCR_CB2_IND_NEG_E
  sta PCR

  ;lda #(IERSETCLEAR | ICA2 | ICB2) ; Enable CA2 and CB2 interrupts
  lda #(IERSETCLEAR | ICB2)
  sta IER


display_loop:
  lda #DISPLAY_FIRST_LINE
  jsr move_cursor

  lda BUTTON_DOWN_COUNTER
  jsr display_hex
  ;lda #' '
  ;jsr display_character
  ;lda BUTTON_UP_COUNTER
  ;jsr display_hex

  lda #255
  jsr delay_10_thousandths
  lda #255
  jsr delay_10_thousandths

  lda #PCR_CB2_LOW_OUT
  ;lda #PCR_CB2_HIGH_OUT
  sta PCR
  lda #100
  jsr delay_10_thousandths
  lda #PCR_CB2_IND_POS_E
  ;lda #PCR_CB2_IND_NEG_E
  sta PCR

  bra display_loop


; Interrupt handler - switch memory banks and routines
interrupt:
  pha

  lda #ILED              ; Turn on interrupt activity LED
  tsb PORTA

;  lda IFR
;  and #ICA2
;  beq button_did_not_come_up
;  lda #ICA2
;  sta IFR
;  inc BUTTON_UP_COUNTER
;button_did_not_come_up:
  lda IFR
  and #ICB2
  beq button_did_not_go_down
  lda #ICB2
  sta IFR
  inc BUTTON_DOWN_COUNTER
button_did_not_go_down:

  lda #100
  jsr delay_10_thousandths

  lda #ILED              ; Turn off interrupt activity LED
  trb PORTA

  pla
  rti                    ; Return to the program in the incoming bank


; Vectors
  .org $fffc
  .word reset
  .word interrupt
