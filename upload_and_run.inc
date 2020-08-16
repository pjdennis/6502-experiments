  .include base_config_v1.inc

;BPS_HUNDREDS          =  96     ;  9600 bps
;BPS_HUNDREDS          = 192     ; 19200 bps
;BPS_HUNDREDS          = 384     ; 38400 bps
BPS_HUNDREDS           = 576     ; 57600 bps

HALF_BIT_INTERVAL      = CLOCK_FREQ_KHZ * 5 / BPS_HUNDREDS

; Shared ram locations
DISPLAY_STRING_PARAM   = $00     ; 2 bytes
UPLOAD_P               = $02     ; 2 bytes
UPLOAD_STOP_AT         = $04     ; 2 bytes
UPLOADED_CHECKSUM_P    = $06     ; 2 bytes
UPLOADED_CHECKSUM      = $08     ; 2 bytes
CHECKSUM_P             = $0a     ; 2 bytes
CHECKSUM_VALUE         = $0c     ; 2 bytes

CP_M_DEST_P            = $0e     ; 2 bytes
CP_M_SRC_P             = $10     ; 2 bytes
CP_M_LEN               = $12     ; 2 bytes
WAITING_FOR_SHIFT      = $14
TEMP                   = $15

TRANSLATE              = $0200
INTERRUPT_ROUTINE      = $3f00

  .org ORIGIN
  jmp program_start

  ; Place code for delay_routines at start of page to ensure no page boundary crossings
  ; during timing loops
  .include delay_routines.inc

  .include display_routines.inc
  .include convert_to_hex.inc
  .include copy_memory.inc

loading_message:          asciiz 'Load 0000 / '
checksum_failed_message:  asciiz 'Checksum failed!'

program_start:
  ldx #$ff ; Initialize stack
  txs

  lda #0   ; Initialize status flags
  pha
  plp

  jsr build_translate

  ; Initialize 6522 port A (memory banking control)
  lda #BANK_START
  sta PORTA
  lda #BANK_MASK                 ; Set pin direction on port A
  sta DDRA

  ; Initialize 6522 port B (display control)
  lda #0
  sta PORTB
  lda #DISPLAY_BITS_MASK         ; Set pin direction on port B
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

  stz WAITING_FOR_SHIFT

  lda #<UPLOAD_TO
  sta UPLOAD_P
  lda #>UPLOAD_TO
  sta UPLOAD_P + 1

  lda #ACR_SR_IN_T2
  sta ACR

  lda #PCR_CB2_IND_NEG_E
  sta PCR

  lda #ICB2
  sta IFR
  lda #(IERSETCLEAR | ICB2)
  sta IER

  lda #<ready_message
  ldx #>ready_message
  jsr display_string

wait_for_length:
  ; Comparison - jump back to wait_for_upload_start if UPLOAD_P < UPLOAD_TO + 2
  ; Taken from here: http://www.6502.org/tutorials/compare_beyond.html
  ; Comparison is safe without locking pointer since it's increasing monatomically
  ; and we compare high bytes first
  lda UPLOAD_P + 1               ; Compare high bytes
  cmp #>(UPLOAD_TO + 2)
  bcc wait_for_length
  bne length_available
  lda UPLOAD_P                   ; Compare low bytes
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
  ; Comparison - upload done if  UPLOAD_P >= UPLOAD_STOP_AT
  ; Taken from here: http://www.6502.org/tutorials/compare_beyond.html
  ; Comparison is safe without locking pointer since it's increasing monatomically
  ; and we compare high bytes first
  lda UPLOAD_P + 1               ; Compare high bytes
  cmp UPLOAD_STOP_AT + 1
  bcc upload_not_done
  bne upload_done
  lda UPLOAD_P                   ; Compare low bytes
  cmp UPLOAD_STOP_AT
  bcs upload_done

upload_not_done:
  lda #(DISPLAY_FIRST_LINE + 5)
  jsr move_cursor

  ; Calculate number of bytes uploaded so far
  sec
  lda UPLOAD_P + 1
  sbc #>(UPLOAD_TO + 2)
  jsr display_hex
  lda #0
  jsr display_hex

  ; Delay for 10 milliseconds
  lda #100
  jsr delay_10_thousandths

  bra wait_for_done

upload_done:
  ; Restore interrupt functionality
  sei
  stz ACR                        ; Disable shifting
  stz PCR                        ; Turn off CB2 interrupts
  lda #(ICB2 | ISR)              ; Disable and reset interrupt flags
  sta IER
  sta IFR
  cli  

  .ifdef UPLOAD_RAM
  ;jsr initialize_restart_handler
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

  ldx CP_M_LEN                   ; Low byte of count
  ldy CP_M_LEN + 1               ; High byte of count

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


build_translate:
  pha
  phx
  phy

  ldx #0
build_translate_loop:
  txa
  ldy #8
build_translate_shift_loop: 
  asl
  ror TEMP
  dey
  bne build_translate_shift_loop
  
  lda TEMP
  sta TRANSLATE,X

  inx
  bne build_translate_loop

  ply
  plx
  pla
  rts


; Interrupt handler - Read in serial data
interrupt:                       ; 7 + 2 (avg) cycles to get into the handler
  pha

  lda WAITING_FOR_SHIFT
  bne interrupt_shift_done

interrupt_serial_in_start:
  lda #(HALF_BIT_INTERVAL * 2 - 2 - 24)       ; 2
  sta T2CL                                    ; 4
  stz T2CH                                    ; 4

  lda #(HALF_BIT_INTERVAL - 2)
  sta T2CL

  lda SR   ; Start shifting

  inc WAITING_FOR_SHIFT
  
  lda #ICB2
  sta IER

  lda #(IERSETCLEAR | ISR)
  sta IER

  bra interrupt_done

interrupt_shift_done:
  phx
  ldx SR                                      ; Clears interrupt
  lda #ACR_SR_IN_T2
  stz ACR
  sta ACR
  lda TRANSLATE,X
  plx
  sta (UPLOAD_P)
  inc UPLOAD_P
  bne interrupt_upload_incremented
  inc UPLOAD_P + 1
interrupt_upload_incremented:
  dec WAITING_FOR_SHIFT

  lda #ICB2
  sta IFR
  lda #(IERSETCLEAR | ICB2)
  sta IER

interrupt_done:
  pla
  rti
interrupt_end:
