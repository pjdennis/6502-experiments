;Requires BPS_HUNDREDS
;BPS_HUNDREDS          =   96     ;   9600 bps
;BPS_HUNDREDS          =  192     ;  19200 bps
;BPS_HUNDREDS          =  384     ;  38400 bps
;BPS_HUNDREDS          =  576     ;  57600 bps
;BPS_HUNDREDS          = 1152     ; 115200 bps
;BPS_HUNDREDS          = 2304     ; 230400 bps

  .if CLOCK_FREQ_KHZ > 6553
HALF_BIT_INTERVAL      = CLOCK_FREQ_KHZ / (BPS_HUNDREDS / 5)
  .else
HALF_BIT_INTERVAL      = CLOCK_FREQ_KHZ * 5 / BPS_HUNDREDS
  .endif

CLOCK_FREQ_MHZ_DIV_100 = CLOCK_FREQ_KHZ / 10

; -2 -26 is the most that can be reduced at 57600 without causing the shift
; start to be delayed... presuming anything less results in T2 expiring before
; the low order latch has been reset
INITIAL_INTERVAL       = HALF_BIT_INTERVAL * 2 - 2 - 24
SUBSEQUENT_INTERVAL    = HALF_BIT_INTERVAL - 2

DISPLAY_DO_NOT_DISABLE_INTERRUPTS = 1

; Shared ram locations
DISPLAY_STRING_PARAM        = $00    ;  2 bytes
DISPLAY_HEX_INDIRECT_PARAM: = $02    ;  2 bytes
UPLOAD_P:                   = $04    ;  2 bytes
UPLOAD_STOP_AT:             = $06    ;  2 bytes
TEMP_P:                     = $08    ;  2 bytes
UPLOADED_CHECKSUM:          = $0a    ;  2 bytes
CHECKSUM_VALUE:             = $0c    ;  2 bytes
CP_M_DEST_P:                = $0e    ;  2 bytes
CP_M_SRC_P:                 = $10    ;  2 bytes
CP_M_LEN:                   = $12    ;  2 bytes
WAITING_FOR_SHIFT:          = $14    ;  1 byte
TEMP:                       = $15    ;  2 byte
TO_DECIMAL_PARAM:           = $16    ; 10 bytes


TRANSLATE                  = $0200
INTERRUPT_ROUTINE          = $3f00

  .org ORIGIN
  jmp initialize_machine

  ; Place code for delay_routines at start of page to ensure no page boundary crossings
  ; during timing loops
  .include delay_routines.inc

  .include display_string.inc
  .include display_hex_indirect.inc
  .include display_decimal.inc
  .include copy_memory.inc

ready_message:            .asciiz 'Ready.'
loading_message:          .asciiz 'Load 0000 / '
checksum_failed_message:  .asciiz 'Checksum failed!'
mhz_message:              .asciiz 'Mhz '
bps_message:              .asciiz '00bps '

program_start:
  ldx #$ff ; Initialize stack
  txs

  cld      ; In case I ever use an NMOS 6502

  .ifdef SHOULD_SWITCH_TO_RAM
  jmp switch_to_ram
  .endif
switch_to_ram_continue:


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

  .ifdef RAM_IRQ_VECTOR

  ; store interrupt vector into the ram location to support vector pull redirecting to ram
  lda #<INTERRUPT_ROUTINE
  sta RAM_IRQ_VECTOR
  lda #>INTERRUPT_ROUTINE
  sta RAM_IRQ_VECTOR + 1

  .endif

  jsr build_translate

  stz WAITING_FOR_SHIFT

  lda #<UPLOAD_TO
  sta UPLOAD_P
  lda #>UPLOAD_TO
  sta UPLOAD_P + 1

  lda #PCR_CB2_IND_NEG_E          ; CB2 independent interrupt negative edge
  sta PCR

  lda #ICB2                       ; Clear any pending CB2 interrupt
  sta IFR
  lda #(IERSETCLEAR | ICB2 | ISR) ; Enable interrupts for SR and CB2
  sta IER

  lda #INITIAL_INTERVAL
  sta T2CL

  cli

  lda #<CLOCK_FREQ_MHZ_DIV_100
  ldx #>CLOCK_FREQ_MHZ_DIV_100
  ldy #2
  jsr display_decimal_with_places
  lda #<mhz_message
  ldx #>mhz_message
  jsr display_string

  lda #'('
  jsr display_character
  lda #<origin_message
  ldx #>origin_message
  jsr display_string
  lda #')'
  jsr display_character

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor

  lda #<BPS_HUNDREDS
  ldx #>BPS_HUNDREDS
  jsr display_decimal
  lda #<bps_message
  ldx #>bps_message
  jsr display_string

  lda #<ready_message
  ldx #>ready_message
  jsr display_string

wait_for_length:
  ; Comparison - jump back to wait_for_upload_start if UPLOAD_P < UPLOAD_TO + 2
  ; Taken from here: http://www.6502.org/tutorials/compare_beyond.html
  ; Comparison is safe without locking pointer since it's increasing monatomically
  ; and we compare high bytes first
  lda UPLOAD_P + 1                ; Compare high bytes
  cmp #>(UPLOAD_TO + 2)
  bcc wait_for_length
  bne length_available
  lda UPLOAD_P                    ; Compare low bytes
  cmp #<(UPLOAD_TO + 2)
  bcc wait_for_length

length_available:
  ldx UPLOAD_TO
  lda TRANSLATE,X
  sta CP_M_LEN
  ldx UPLOAD_TO + 1
  lda TRANSLATE,X
  sta CP_M_LEN + 1

  clc                             ; Add length to upload location
  lda #<UPLOAD_TO
  adc CP_M_LEN
  tax
  lda #>UPLOAD_TO
  adc CP_M_LEN + 1
  tay

  clc                             ; Add 4 extra bytes (length and checksum)
  txa
  adc #4
  sta UPLOAD_STOP_AT
  tya
  adc #0
  sta UPLOAD_STOP_AT + 1

  jsr clear_display               ; Display the 'loading' message...

  lda #<loading_message
  ldx #>loading_message
  jsr display_string

  lda #<CP_M_LEN                  ; ...and display total size to be uploaded
  ldx #>CP_M_LEN
  jsr display_hex_indirect_2_bytes

wait_for_done:
  ; Comparison - upload done if  UPLOAD_P >= UPLOAD_STOP_AT
  ; Taken from here: http://www.6502.org/tutorials/compare_beyond.html
  ; Comparison is safe without locking pointer since it's increasing monatomically
  ; and we compare high bytes first
  lda UPLOAD_P + 1                ; Compare high bytes
  cmp UPLOAD_STOP_AT + 1
  bcc upload_not_done
  bne upload_done
  lda UPLOAD_P                    ; Compare low bytes
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
  stz ACR                         ; Disable shifting
  stz PCR                         ; Turn off CB2 interrupts
  lda #(ICB2 | ISR)               ; Disable and reset interrupt flags
  sta IER
  sta IFR
  cli  

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

  ; Translate data (reverse the bit order)
  jsr translate_data

  ; Calculate checksum
  jsr calculate_checksum

  ; Obtain uploaded checksum
  clc
  lda #<(UPLOAD_TO + 2)
  adc CP_M_LEN
  sta TEMP_P
  lda #>(UPLOAD_TO + 2)
  adc CP_M_LEN + 1
  sta TEMP_P + 1

  lda (TEMP_P)
  sta UPLOADED_CHECKSUM
  ldy #1
  lda (TEMP_P),Y
  sta UPLOADED_CHECKSUM + 1

  ; Compare checksums
  lda CHECKSUM_VALUE
  cmp UPLOADED_CHECKSUM
  bne bad_checksum
  lda CHECKSUM_VALUE + 1
  cmp UPLOADED_CHECKSUM + 1
  bne bad_checksum

; Good checksum  
  jsr copy_memory                 ; Relocate upload to the correct location for running it
  sei                             ; Disable interrupts, as they are after a reset
  jmp UPLOAD_TO                   ; Jump to and run the main program

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
  lda #<CP_M_LEN
  ldx #>CP_M_LEN
  jsr display_hex_indirect_2_bytes

  lda #' '
  jsr display_character

  ; Display the uploaded checksum
  lda #<UPLOADED_CHECKSUM
  ldx #>UPLOADED_CHECKSUM
  jsr display_hex_indirect_2_bytes

  lda #' '
  jsr display_character

  ; Display the calculated checksum
  lda #<CHECKSUM_VALUE
  ldx #>CHECKSUM_VALUE
  jsr display_hex_indirect_2_bytes

forever:
  bra forever


translate_data:
  lda CP_M_SRC_P
  sta TEMP_P
  lda CP_M_SRC_P + 1
  sta TEMP_P + 1

  ; Translate count + 2 bytes, to include checksum
  clc
  lda CP_M_LEN
  adc #2
  tax                             ; Low byte of count
  lda CP_M_LEN + 1
  adc #0
  tay                             ; High byte of count

translate_loop:
  cpy #0
  bne translate_not_done
  cpx #0
  beq translate_done
translate_not_done:
  phx
  lda (TEMP_P)
  tax
  lda TRANSLATE,X
  sta (TEMP_P)
  plx

  inc TEMP_P
  bne translate_p_increment_done
  inc TEMP_P + 1
translate_p_increment_done:

  dex
  cpx #$ff
  bne translate_loop
  dey
  bra translate_loop

translate_done:
  rts


; On exit A, X, Y are not preserved
calculate_checksum:
  stz CHECKSUM_VALUE
  stz CHECKSUM_VALUE + 1

  lda CP_M_SRC_P
  sta TEMP_P
  lda CP_M_SRC_P + 1
  sta TEMP_P + 1

  ldx CP_M_LEN                    ; Low byte of count
  ldy CP_M_LEN + 1                ; High byte of count

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
  lda (TEMP_P)
  adc CHECKSUM_VALUE
  sta CHECKSUM_VALUE
  lda #0
  adc CHECKSUM_VALUE + 1
  sta CHECKSUM_VALUE + 1

  inc TEMP_P
  bne checksum_p_increment_done
  inc TEMP_P + 1
checksum_p_increment_done:

  dex
  cpx #$ff
  bne checksum_loop
  dey
  bra checksum_loop

checksum_done:
  rts


; On exit A, X, Y are not preserved
build_translate:
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

  rts


; Interrupt handler - Read in serial data
interrupt:                        ; 7 + 2 (avg) cycles to get into the handler
  pha                             ; 3

  lda WAITING_FOR_SHIFT           ; 3
  bne interrupt_shift_done        ; 2 (not taken) 3 (taken)

interrupt_serial_in_start:        ;                  - 17 cycles to get here
  lda #ACR_SR_IN_T2               ; 2 Reenable the shift register
  sta ACR                         ; 4

  stz T2CH                        ; 4 Start timer for the initial interval before shift starts

  lda SR                          ; 4 Start shifting - 31 cycles to get to here

  lda #SUBSEQUENT_INTERVAL        ; 2
  sta T2CL                        ; 4 Interval set   - 37 cycles to get here

  lda #ICB2                       ; Disable CB2 interrupts while shift is in progress
  sta IER

  inc WAITING_FOR_SHIFT           ; Indicate we're waiting for completed shift

  pla
  rti

interrupt_shift_done:             ;                  - 18 cycles to get here
  stz ACR                         ; 4 Disable the timer temporarily

  lda #ICB2                       ; 2 Clear pending ICB2 interrupt
  sta IFR                         ; 4
  lda #(IERSETCLEAR | ICB2)       ; 2 Reenable CB2 interrupts
  sta IER                         ; 4

  lda #INITIAL_INTERVAL           ; 2 Pre-load initial interval to T2
  sta T2CL                        ; 4

  lda SR                          ; 4 Load value; clears SR interrupt as a side effect

  stz WAITING_FOR_SHIFT           ; 3 Indicate we're no longer waiting for completed shift

  cli                             ; 2 Renable interrupts so that start of shift can occur
                                  ;                  - 49 cycles to get here

  nop                             ; Noops provide a window for low-latency response
  nop                             ; To the CB2 interrupt indicating shift start
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

  sta (UPLOAD_P)                  ; Now store the value that was received...
  inc UPLOAD_P                    ; ...and increment the data pointer
  bne interrupt_upload_incremented
  inc UPLOAD_P + 1
interrupt_upload_incremented:

  pla
  rti

interrupt_end:
