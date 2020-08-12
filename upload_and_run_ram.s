PORTB = $6000
PORTA = $6001
DDRB  = $6002
DDRA  = $6003

; PORTA assignments
BANK_MASK         = %00001111
ILED              = %00010000
;LED              = %00100000
BUTTON            = %00100000
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

CLOCK_FREQ_KHZ           = 2000
;BIT_TIMER_INTERVAL      =  208 - 1 ; 2 MHz 9600  bps;  1 MHz 4800  bps ; 2 byte counter
;BIT_TIMER_INTERVAL      =  104 - 1 ; 2 MHz 19200 bps;  1 MHz 9600  bps ; "
BIT_TIMER_INTERVAL       =   52 - 1 ; 2 MHz 38400 bps;  1 MHz 19200 bps ; 1 byte counter
;BIT_TIMER_INTERVAL      =   69 - 1 ; 4 MHz / 57600 bps
;BIT_TIMER_INTERVAL      =  104 - 1 ; 4 MHz / 38400 bps
;BIT_TIMER_INTERVAL      = 3333 - 1 ; 1 MHz / 300 bps

ICB2_TO_T1_START         = 19
IT1_TO_READ              = 20

;FIRST_BIT_TIMER_INTERVAL = BIT_TIMER_INTERVAL * 1.33 - ICB2_TO_T1_START - IT1_TO_READ
FIRST_BIT_TIMER_INTERVAL = BIT_TIMER_INTERVAL * 1.5 - ICB2_TO_T1_START - IT1_TO_READ

NUMBER_OF_BITS           = 8    ; Not counting start or stop bits. There's no parity bit.
STATE_WAITING_FOR_CB2    = 0
STATE_WAITING_FOR_TIMER  = 1

; Shared ram locations
DISPLAY_STRING_PARAM     = $00 ; 2 bytes
UPLOAD_LOCATION          = $02 ; 2 bytes
UPLOAD_STOP_AT           = $04 ; 2 bytes
UPLOADED_CHECKSUM_P      = $06 ; 2 bytes
UPLOADED_CHECKSUM        = $08 ; 2 bytes
UPLOAD_LOCATION_COPY     = $0a ; 2 bytes
CHECKSUM_P               = $0c ; 2 bytes
CHECKSUM_VALUE           = $0e ; 2 bytes

CP_M_DEST_P              = $10 ; 2 bytes
CP_M_SRC_P               = $12 ; 2 bytes
CP_M_LEN                 = $14 ; 2 bytes

BIT_VALUE                = $16
SERIAL_WAITING           = $17

; For EEPROM Operation
;UPLOAD_TO               = $2000
; For RAM Testing
UPLOAD_TO                = $3000

INTERRUPT_ROUTINE        = $3f00

; For EEPROM Operation:
; .org $8000
; ...end

; For RAM Operation:
  .org $2000
  jmp program_start
; ...end

  ; Place code for delay_routines at start of page to ensure no page boundary crossings
  ; during timing loops
  .include delay_routines.inc

  .include display_routines.inc
  .include convert_to_hex.inc
  .include copy_memory.inc

program_start:
  ldx #$ff ; Initialize stack
  txs

  lda #0   ; Initialize status flags
  pha
  plp

  ; Initialize 6522 port A (memory banking control)
  lda #BANK_START
  sta PORTA
  lda #(BANK_MASK | ILED) ; Set pin direction  on port A
  sta DDRA

  ; Initialize 6522 port B (display control)
  lda #0
  sta PORTB
  lda #(DISPLAY_BITS_MASK | T1_SQWAVE_OUT) ; Set display pins and T1 output pins to output
  sta DDRB

  ; Initialize display
  jsr reset_and_enable_display_no_cursor

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

  lda #<UPLOAD_TO
  sta UPLOAD_LOCATION
  lda #>UPLOAD_TO
  sta UPLOAD_LOCATION + 1

  ; Configure T1 continuous clock
  lda #ACR_T1_CONT
  sta ACR  

  ; Configure CB2 for independent interrupt; Negative edge because we're not inverting
  ; the incoming serial receive line to adapt voltage levels
  lda #PCR_CB2_IND_NEG_E
  sta PCR

  ; Initialize for serial receive
  lda #<FIRST_BIT_TIMER_INTERVAL  ; Load timer duration to center of first bit
  sta T1CL

  lda #1
  sta SERIAL_WAITING

  lda #$80
  sta BIT_VALUE

  lda #(IERSETCLEAR | ICB2 | IT1) ; Enable CB2 and timer interrupts
  sta IER

  lda #<ready_message
  ldx #>ready_message
  jsr display_string

wait_for_length:
  sei
  lda UPLOAD_LOCATION
  ldx UPLOAD_LOCATION + 1
  cli

  sta UPLOAD_LOCATION_COPY
  stx UPLOAD_LOCATION_COPY + 1

  ; Comparison - jump back to wait_for_upload_start if UPLOAD_LOCATION < UPLOAD_TO + 2
  ; Taken from here: http://www.6502.org/tutorials/compare_beyond.html
  lda UPLOAD_LOCATION_COPY + 1   ; Compare high bytes
  cmp #>(UPLOAD_TO + 2)
  bcc wait_for_length
  bne length_available
  lda UPLOAD_LOCATION_COPY       ; Compare low bytes
  cmp #<(UPLOAD_TO + 2)
  bcc wait_for_length

length_available:
  clc                            ; Add length to upload location
  lda #<UPLOAD_TO
  adc UPLOAD_TO
  tax
  lda #>UPLOAD_TO
  adc UPLOAD_TO + 1
  tay
  clc
  txa
  adc #4                         ; Add 4 extra bytes (length and checksum)
  sta UPLOAD_STOP_AT
  tya
  adc #0
  sta UPLOAD_STOP_AT + 1

  jsr clear_display

  lda #<loading_message
  ldx #>loading_message
  jsr display_string

  lda UPLOAD_TO + 1
  jsr display_hex
  lda UPLOAD_TO
  jsr display_hex

wait_for_done:
  sei
  lda UPLOAD_LOCATION
  ldx UPLOAD_LOCATION + 1
  cli

  sta UPLOAD_LOCATION_COPY
  stx UPLOAD_LOCATION_COPY + 1

  ; Comparison - upload done if  UPLOAD_LOCATION >= UPLOAD_STOP_AT
  ; Taken from here: http://www.6502.org/tutorials/compare_beyond.html
  lda UPLOAD_LOCATION_COPY + 1   ; Compare high bytes
  cmp UPLOAD_STOP_AT + 1
  bcc upload_not_done
  bne upload_done
  lda UPLOAD_LOCATION_COPY       ; Compare low bytes
  cmp UPLOAD_STOP_AT
  bcs upload_done

upload_not_done:
  lda #(DISPLAY_FIRST_LINE + 5)
  jsr move_cursor

  sec
  lda UPLOAD_LOCATION_COPY
  sbc #<(UPLOAD_TO + 2)
  tax
  lda UPLOAD_LOCATION_COPY + 1
  sbc #>(UPLOAD_TO + 2)
  jsr display_hex
  txa
  jsr display_hex

  lda #100
  jsr delay_10_thousandths

  bra wait_for_done

upload_done:
  lda #0                         ; Set CB2 back to default behavior
  sta PCR 

  lda #(IT1 | ICB2) ; Disable T1 and CB2 interrupts
  sta IER

  ; Point interrupt handler to reset routine
  lda #$4c                       ; jmp opcode
  sta INTERRUPT_ROUTINE
  lda #<reset_interrupt
  sta INTERRUPT_ROUTINE + 1
  lda #>reset_interrupt
  sta INTERRUPT_ROUTINE + 2

  ; Configure and enable CA2 independent interrupts
  lda #PCR_CA2_IND_NEG_E
  sta PCR
  lda #(IERSETCLEAR | ICA2)
  sta IER

  lda #<UPLOAD_TO
  sta CP_M_DEST_P
  lda #>UPLOAD_TO
  sta CP_M_DEST_P + 1

  lda #<(UPLOAD_TO + 2)
  sta CP_M_SRC_P
  lda #>(UPLOAD_TO + 2)
  sta CP_M_SRC_P + 1

  lda UPLOAD_TO
  sta CP_M_LEN
  lda UPLOAD_TO + 1
  sta CP_M_LEN + 1

  jsr calculate_checksum

  ; Obtain uploaded checksum
  sec
  lda UPLOAD_STOP_AT
  sbc #2
  sta UPLOADED_CHECKSUM_P
  lda UPLOAD_STOP_AT + 1
  sbc #0
  sta UPLOADED_CHECKSUM_P + 1

  ldy #0
  lda (UPLOADED_CHECKSUM_P),Y
  sta UPLOADED_CHECKSUM
  iny
  lda (UPLOADED_CHECKSUM_P),Y
  sta UPLOADED_CHECKSUM + 1

  jsr clear_display

  ; Compare checksums
  lda CHECKSUM_VALUE
  cmp UPLOADED_CHECKSUM
  bne bad_checksum
  lda CHECKSUM_VALUE + 1
  cmp UPLOADED_CHECKSUM + 1
  bne bad_checksum

; Good checksum
  
  jsr copy_memory                ; Relocate upload to the correct location for running it
  jmp UPLOAD_TO                  ; Jump to and run the main program

bad_checksum:
  lda #<checksum_failed_message
  ldx #>checksum_failed_message
  jsr display_string

  lda #(DISPLAY_SECOND_LINE)
  jsr move_cursor

  lda #'L'
  jsr display_character
  lda #' '
  jsr display_character

  ; Display The length uploaded
  lda CP_M_LEN + 1
  jsr display_hex
  lda CP_M_LEN
  jsr display_hex

  lda #' '
  jsr display_character

  ; Display the uploaded checksum
  lda UPLOADED_CHECKSUM + 1
  jsr display_hex
  lda UPLOADED_CHECKSUM
  jsr display_hex

  lda #' '
  jsr display_character

  ; Display the calculated checksum
  lda CHECKSUM_VALUE + 1
  jsr display_hex
  lda CHECKSUM_VALUE
  jsr display_hex

keep_waiting:
  bra keep_waiting


stop_here:
  lda #DISPLAY_SECOND_LINE + 15
  jsr move_cursor

  lda #'.'
  jsr display_character
forever:
  bra forever


ready_message:            asciiz 'Ready (RAM).'
loading_message:          asciiz 'Load 0000 / '
loaded_message:           asciiz 'Loaded '
checksum_failed_message:  asciiz 'Checksum failed!'


display_string:
  sta DISPLAY_STRING_PARAM
  stx DISPLAY_STRING_PARAM + 1
  ldy #0
print_loop:
  lda (DISPLAY_STRING_PARAM),Y
  beq done_printing
  jsr display_character
  iny
  jmp print_loop
done_printing:
  rts


wait_for_button:
  lda PORTA
  and #BUTTON
  bne wait_for_button
wait_button_up:
  ldy #5
wait_button_up_loop:
  lda #100
  jsr delay_10_thousandths
  lda PORTA
  and #BUTTON
  beq wait_button_up
  dey
  bne wait_button_up_loop
  rts

; On exit A, X, Y are preserved
calculate_checksum:
  pha
  phx
  phy

  stz CHECKSUM_VALUE
  stz CHECKSUM_VALUE + 1

  lda CP_M_SRC_P
  sta CHECKSUM_P
  lda CP_M_SRC_P + 1
  sta CHECKSUM_P + 1

  ldx CP_M_LEN          ; Low byte of count
  ldy CP_M_LEN + 1      ; High byte of count

checksum_loop:
  cpy #0
  bne checksum_not_done
  cpx #0
  beq checksum_done
checksum_not_done:

  lda CHECKSUM_VALUE + 1
  ror
  ror CHECKSUM_VALUE
  ror CHECKSUM_VALUE + 1

  clc
  lda (CHECKSUM_P)
  adc CHECKSUM_VALUE
  sta CHECKSUM_VALUE
  lda #0
  adc CHECKSUM_VALUE + 1
  sta CHECKSUM_VALUE + 1

  inc CHECKSUM_P
  bne checksum_p_increment_done
  inc CHECKSUM_P + 1
checksum_p_increment_done:

  dex
  cpx #$ff
  bne checksum_loop
  dey
  bra checksum_loop

checksum_done:
  ply
  plx
  pla
  rts


; Triggered by CA2 negative edge
reset_interrupt:
  ; Clear and reset CA2 interrupts
  lda #0
  sta PCR
  lda #ICA2
  sta IER
  sta IFR

  jmp program_start


; Interrupt handler - Read in serial data
interrupt:                       ; 7 cycles to get into the handler
  pha                            ; 3

  lda SERIAL_WAITING             ; 3 (zero page)
  beq timer_interrupt            ; 2 (when not taken)


cb2_interrupt:

; This code for slower speeds    ;
; lda #>FIRST_BIT_TIMER_INTERVAL ; 2 Start the timer (low byte already in latch)
; sta T1CH                       ; 4 (Starts at about 21 cycles in)
;                                ;
; lda #<BIT_TIMER_INTERVAL       ; 2 Load bit-to-bit timer duration into latches
; sta T1LL                       ; 4
; lda #>BIT_TIMER_INTERVAL       ; 2 ; Commenting this assumes FIRST_BIT_TIMER_INTERVAL < 256
; sta T1LH                       ; 4
; End of code for slower speeds  ;

; This code for faster speeds    ;
  stz T1CH                       ; 4 Assumes FIRST_BIT_TIMER_INTERVAL < 256 (19 cycles in)
                                 ;
  lda #<BIT_TIMER_INTERVAL       ; 2 Load bit-to-bit timer duration into latches
  sta T1LL                       ; 4
; End of code for faster speeds  ;

  lda #ICB2                      ; 2 Disable the CB2 interrupt
  sta IER                        ; 4

  stz SERIAL_WAITING             ; 3 (zero page)
 
  ; Dup of interrupt_done code
  pla                            ; 4
  rti                            ; 6 (About 25 cycles to get out)

timer_interrupt:
  lda PORTA                      ; 4 (read at 20 cycles in)

; This code for using an arbitrary pin for serial
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
  lda #ILED                      ; Turn on interrupt activity LED
  tsb PORTA

; Stop timer 1 while keeping timer interrupts enabled
  stz ACR                        ; 4 Timer to 1 shot mode
  stz T1CL                       ; 4 Load a 0 into the timer; will expire after one cycle
  stz T1CH                       ; 4

  lda BIT_VALUE                  ; 3 (zero page)
  sta (UPLOAD_LOCATION)
  inc UPLOAD_LOCATION
  bne upload_location_incremented
  inc UPLOAD_LOCATION + 1

upload_location_incremented:
  lda #(IT1 | ICB2)              ; Clear the timer and cb2 interrupt flags
  sta IFR                        ; 4

; Reset serial state
  lda #<FIRST_BIT_TIMER_INTERVAL ; 2 Load timer duration to center of first bit
  sta T1CL                       ; 4

  lda #1                         ; 2
  sta SERIAL_WAITING             ; 4

  lda #$80                       ; 2
  sta BIT_VALUE                  ; 4

  lda #(IERSETCLEAR | ICB2)      ; 2 Renable CB2 interrupts
  sta IER                        ; 4

  ; Configure T1 continuous clock
  lda #ACR_T1_CONT
  sta ACR 

  lda #ILED                      ; Turn off interrupt activity LED
  trb PORTA

interrupt_done:
  pla                            ; 4
  rti                            ; 6 Return to the program in the incoming bank
interrupt_end:

; For EEPROM Operation
; Vectors
;  .org $fffc
;  .word reset
;  .word INTERRUPT_ROUTINE
