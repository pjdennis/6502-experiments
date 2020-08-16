  .include base_config_v1.inc

;BIT_TIMER_INTERVAL      =  208 - 1 ; 2 MHz 9600  bps;  1 MHz 4800  bps ; 2 byte counter
;BIT_TIMER_INTERVAL      =  104 - 1 ; 2 MHz 19200 bps;  1 MHz 9600  bps ; "
BIT_TIMER_INTERVAL       =   52 - 1 ; 2 MHz 38400 bps;  1 MHz 19200 bps ; 1 byte counter
;BIT_TIMER_INTERVAL      =   69 - 1 ; 4 MHz / 57600 bps
;BIT_TIMER_INTERVAL      =  104 - 1 ; 4 MHz / 38400 bps

ICA2_TO_T1_START         = 19
IT1_TO_READ              = 20

FIRST_BIT_TIMER_INTERVAL = BIT_TIMER_INTERVAL * 1.5 - ICA2_TO_T1_START - IT1_TO_READ

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

INTERRUPT_ROUTINE        = $3f00

  .org ORIGIN
  jmp program_start

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
  lda #BANK_MASK         ; Set pin direction on port A
  sta DDRA

  ; Initialize 6522 port B (display control)
  lda #0
  sta PORTB
  lda #DISPLAY_BITS_MASK ; Set pin direction on port B
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

  ; Configure CA2 for independent interrupt; Negative edge because we're not inverting
  ; the incoming serial receive line to adapt voltage levels
  lda #PCR_CA2_IND_NEG_E
  sta PCR

  ; Initialize for serial receive
  lda #<FIRST_BIT_TIMER_INTERVAL  ; Load timer duration to center of first bit
  sta T1CL

  lda #1
  sta SERIAL_WAITING

  lda #$80
  sta BIT_VALUE

  lda #(IERSETCLEAR | ICA2 | IT1) ; Enable CA2 and timer interrupts
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

  ; Calculate number of bytes uploaded so far
  sec
  lda UPLOAD_LOCATION_COPY
  sbc #<(UPLOAD_TO + 2)
  tax
  lda UPLOAD_LOCATION_COPY + 1
  sbc #>(UPLOAD_TO + 2)
  jsr display_hex
  txa
  jsr display_hex

  ; Delay for 10 milliseconds
  lda #100
  jsr delay_10_thousandths

  bra wait_for_done

upload_done:
  lda #0                         ; Set CA2 back to default behavior
  sta PCR 

  lda #(IT1 | ICA2) ; Disable T1 and CA2 interrupts
  sta IER

  .ifdef UPLOAD_RAM
  jsr initialize_restart_handler
  .endif

  jsr clear_display

  ; Prepare parameters for checksum calculation and memory copy
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

  ; Calculate checksum
  jsr calculate_checksum

  ; Obtain uploaded checksum
  sec
  lda UPLOAD_STOP_AT
  sbc #2
  sta UPLOADED_CHECKSUM_P
  lda UPLOAD_STOP_AT + 1
  sbc #0
  sta UPLOADED_CHECKSUM_P + 1

  lda (UPLOADED_CHECKSUM_P)
  sta UPLOADED_CHECKSUM
  ldy #1
  lda (UPLOADED_CHECKSUM_P),Y
  sta UPLOADED_CHECKSUM + 1

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

forever:
  bra forever


loading_message:          asciiz 'Load 0000 / '
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


; On exit A, X, Y are not preserved
calculate_checksum:
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
  rts


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

  lda #ICA2                      ; 2 Disable the CA2 interrupt
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
  lda #(IT1 | ICA2)              ; Clear the timer and cb2 interrupt flags
  sta IFR                        ; 4

; Reset serial state
  lda #<FIRST_BIT_TIMER_INTERVAL ; 2 Load timer duration to center of first bit
  sta T1CL                       ; 4

  lda #1                         ; 2
  sta SERIAL_WAITING             ; 4

  lda #$80                       ; 2
  sta BIT_VALUE                  ; 4

  lda #(IERSETCLEAR | ICA2)      ; 2 Renable CA2 interrupts
  sta IER                        ; 4

  ; Configure T1 continuous clock
  lda #ACR_T1_CONT
  sta ACR 

interrupt_done:
  pla                            ; 4
  rti                            ; 6 Return to the program in the incoming bank
interrupt_end:
