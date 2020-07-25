PORTB = $6000
PORTA = $6001
DDRB = $6002
DDRA = $6003

; PORTA assignments
BANK              = %00001111

BANK_START        = %00000100
BANK_STOP         = %00010000

ILED              = %00010000
LED               = %00100000
BUTTON1           = %01000000
BUTTON2           = %10000000

; PORTB assignments
DISPLAY_DATA_MASK = %11110000
E                 = %00001000
RW                = %00000100
RS                = %00000010
BF                = %10000000
DISPLAY_BITS_MASK = (DISPLAY_DATA_MASK | E | RW | RS)

FLASH_LED         = %00000001

  .include display_parameters.inc

; 6522 timer registers
T1CL = $6004
T1CH = $6005
ACR  = $600B
IFR  = $600D
IER  = $600E

; 6522 timer flag masks
IERSETCLEAR = %10000000
IT1         = %01000000

DELAY = 1000 ; 1000 1 MHZ cycles = 1 ms

; Memory locations
BUSY_COUNTER           = $0000 ; 2 bytes
STACK_POINTER_SAVE     = $0002
DISPLAY_SCRATCH        = $0003

  .org $8000

  ;Place code for delay_routines at start of page to ensure no page boundary crossings during timing loops
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
  lda #(BANK | LED | ILED) ; Set pin direction  on port A
  sta DDRA

  ; Initialize 6522 port B (display control)
  lda #0
  sta PORTB
  lda #(DISPLAY_BITS_MASK | FLASH_LED) ; Set display control pins and data pins on port B to output
  sta DDRB


  ; Initialize display
  jsr reset_and_enable_display_no_cursor

  ; Print Something
  lda #'X'
  jsr display_character


  jmp run_counter
  jmp flash_led


  ; Configure the second process
  lda #<led_control
  ldx #>led_control
  jsr initialize_second_process


  ; Configure timer
  lda #%01000000 ; Timer 1 free run mode 
  sta ACR
  lda #(IERSETCLEAR | IT1)
  sta IER

  ; Set timer delay which starts timer as a side effect
  lda #<DELAY
  sta T1CL
  lda #>DELAY
  sta T1CH     ; store to the high register starts the timer


  ; Start the main routine
  jmp run_counter


; Routine will flash an LED using busy wait for delay
flash_led:
  sei
  lda PORTB
  ora #FLASH_LED
  sta PORTB
  cli

  jsr delay_tenth

  sei
  lda PORTB
  and #(~FLASH_LED & $ff)
  sta PORTB
  cli

  jsr delay_tenth
  
  jmp flash_led


delay_tenth:
  lda #200
  jsr delay_10_thousandths
  jsr delay_10_thousandths   
  jsr delay_10_thousandths   
  jsr delay_10_thousandths   
  jsr delay_10_thousandths   
  rts


; Routine will switch LED on or off based on button presses
led_control:
  lda PORTA
  and #BUTTON1
  beq led_on
  lda PORTA
  and #BUTTON2
  beq led_off
  jmp led_control
led_on:
  sei
  lda PORTA
  ora #LED
  sta PORTA
  cli
  jmp led_control
led_off:
  sei
  lda PORTA
  and #(~LED & $ff)
  sta PORTA
  cli
  jmp led_control


; Busy loop incrementing and displaying counter
run_counter:
  lda #0
  sta BUSY_COUNTER
  sta BUSY_COUNTER + 1
run_counter_repeat:
  lda #(CMD_SET_DDRAM_ADDRESS | (DISPLAY_SECOND_LINE + 11))
  jsr display_command

  lda BUSY_COUNTER + 1
  jsr convert_to_hex
  jsr display_character
  txa
  jsr display_character

  lda BUSY_COUNTER
  jsr convert_to_hex
  jsr display_character
  txa
  jsr display_character

  inc BUSY_COUNTER
  bne run_counter_repeat
  inc BUSY_COUNTER + 1
  jmp run_counter_repeat


; Set up stack, etc. so that second process will start running on next interrupt
; On entry A = low source address
;          X = high byte source address
initialize_second_process:
  tay            ; low order address in Y

  lda PORTA      ; Switch to bank 1
  ora #%00001000
  sta PORTA

  txa            ; High order address in A

  tsx            ; Save bank 0 stack pointer to save location
  stx STACK_POINTER_SAVE

  ldx #$ff       ; Initialize stack on bank 1
  txs

  ; Set up stack on bank 1 for RTI to start routine
  pha            ; Push high order address
  tya            ; Push low order address
  pha
  lda #0
  pha            ; Push 0 to status flags
  pha            ; Push 'A' = 0
  pha            ; Push 'X' = 0
  pha            ; Push 'Y' = 0

  lda STACK_POINTER_SAVE ; bank 0 stack pointer in A

  ; Save bank 1 stack pointer to save location
  tsx
  stx STACK_POINTER_SAVE

  ; Restore bank 0 stack pointer
  tax
  txs

  lda PORTA      ; Switch to bank 0
  and #(~%00001000 & $ff)
  sta PORTA

  rts


; Interrupt handler - switch memory banks and routines
interrupt:
  ; Save outgoing bank registers to stack
  pha
  jsr interrupt_led_on
  txa
  pha
  tya
  pha

  ; Save outgoing bank stack pointer to save location
  tsx
  stx STACK_POINTER_SAVE

  ; Toggle the memory bank
  lda PORTA
  eor #%00001000
  sta PORTA

  ; Restore incoming bank stack pointer from save location
  ldx STACK_POINTER_SAVE
  txs

  ; reset 6522 timer
  lda #IT1
  sta IFR

  ; Restore incoming bank registers from stack
  pla
  tay
  pla
  tax
  jsr interrupt_led_off
  pla

  rti


interrupt_led_on:
  lda PORTA
  ora #ILED
  sta PORTA
  rts


interrupt_led_off:
  lda PORTA
  and #(~ILED & $ff)
  sta PORTA
  rts


; Vectors
  .org $fffc
  .word reset
  .word interrupt
