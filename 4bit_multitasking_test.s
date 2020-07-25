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

;DELAY = 1000 ; 1000 1 MHZ cycles = 1 ms
;DELAY = 2000 ; 2000 microseconds = 2 milliseconds; rate = 500 Hz
DELAY = 3822; 261.6 Hz; 'Middle C' 

BUSY_COUNTER_DELTA     = 1

; Banked memory locations
BUSY_COUNTER           = $0000 ; 2 bytes
BUSY_COUNTER_INCREMENT = $0002 ; 2 bytes
BUSY_COUNTER_LOCATION  = $0004
STACK_POINTER_SAVE     = $0005
DISPLAY_SCRATCH        = $0006
TASK_SWITCH_SCRATCH    = $0007

; Shared memory locations 
FIRST_UNUSED_BANK      = $2000
SCREEN_LOCK            = $2001

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

  ; Initialize process control area
  lda #(BANK_START + 1)
  sta FIRST_UNUSED_BANK

  lda #0
  sta SCREEN_LOCK

  ; Initialize display
  jsr reset_and_enable_display_no_cursor


  ; Configure the additional processes
  lda #<run_counter_top_left
  ldx #>run_counter_top_left
  jsr initialize_additional_process

  lda #<run_counter_top_right
  ldx #>run_counter_top_right
  jsr initialize_additional_process

  lda #<run_counter_bottom_left
  ldx #>run_counter_bottom_left
  jsr initialize_additional_process

  lda #<run_counter_bottom_right
  ldx #>run_counter_bottom_right
  jsr initialize_additional_process

  lda #<run_chase
  ldx #>run_chase
  jsr initialize_additional_process

  lda #<flash_led
  ldx #>flash_led
  jsr initialize_additional_process


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
  jmp led_control


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
run_counter_top_left:
  lda #BUSY_COUNTER_DELTA
  ldx #(DISPLAY_FIRST_LINE + 0)
  jmp run_counter

; Busy loop incrementing and displaying counter
run_counter_top_right:
  lda #(-BUSY_COUNTER_DELTA)
  ldx #(DISPLAY_FIRST_LINE + 12)
  jmp run_counter

; Busy loop incrementing and displaying counter
run_counter_bottom_left:
  lda #(-BUSY_COUNTER_DELTA)
  ldx #(DISPLAY_SECOND_LINE + 0)
  jmp run_counter

; Busy loop incrementing and displaying counter
run_counter_bottom_right:
  lda #BUSY_COUNTER_DELTA
  ldx #(DISPLAY_SECOND_LINE + 12)
  jmp run_counter

run_counter:
  stx BUSY_COUNTER_LOCATION

  sta BUSY_COUNTER_INCREMENT
  ldy #0
  tax
  bpl store_counter_increment_high_byte
  dey
store_counter_increment_high_byte:
  sty BUSY_COUNTER_INCREMENT + 1

  lda #0
  sta BUSY_COUNTER
  sta BUSY_COUNTER + 1
run_counter_repeat:
  jsr lock_screen

  lda BUSY_COUNTER_LOCATION
  ora #CMD_SET_DDRAM_ADDRESS
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

  jsr unlock_screen

  ; Add busy counter delta
  lda BUSY_COUNTER
  clc
  adc BUSY_COUNTER_INCREMENT
  sta BUSY_COUNTER
  lda BUSY_COUNTER + 1
  adc BUSY_COUNTER_INCREMENT + 1
  sta BUSY_COUNTER + 1

  lda #100
  jsr delay_10_thousandths

  jmp run_counter_repeat


run_chase:
  ldx #(DISPLAY_FIRST_LINE + 5)

run_chase_right:
  jsr lock_screen
  txa
  pha
  sec
  ora #CMD_SET_DDRAM_ADDRESS
  jsr display_command
  lda #' '
  jsr display_character
  lda #'X'
  jsr display_character
  jsr unlock_screen

  lda #250
  jsr delay_10_thousandths

  pla
  tax
  inx
  cpx #(DISPLAY_FIRST_LINE + 10)
  bne run_chase_right

  ldx #(DISPLAY_FIRST_LINE + 9)

run_chase_left:
  jsr lock_screen
  txa
  pha
  ora #CMD_SET_DDRAM_ADDRESS
  jsr display_command
  lda #'X'
  jsr display_character
  lda #' '
  jsr display_character
  jsr unlock_screen

  lda #125
  jsr delay_10_thousandths

  pla
  tax
  dex
  cpx #(DISPLAY_FIRST_LINE + 4)
  bne run_chase_left
  jmp run_chase
  

lock_screen:
  lda #0
  sei
  cmp SCREEN_LOCK
  beq lock_acquired
  cli
  jmp lock_screen
lock_acquired:
  inc SCREEN_LOCK
  cli
  rts

unlock_screen:
  lda #0
  sta SCREEN_LOCK
  rts


; Set up stack, etc. so that additional process will start running on next interrupt
; On entry A = low source address
;          X = high byte source address
initialize_additional_process:
  tay            ; low order address in Y
  lda FIRST_UNUSED_BANK
  cmp #BANK_STOP
  bne banks_exist
  rts            ; Silently ignore attempts to add too many processes
banks_exist:
  lda PORTA      ; Switch to first unused bank
  and #(~BANK & $ff)
  ora FIRST_UNUSED_BANK
  sta PORTA

  txa            ; High order address in A

  tsx            ; Save first bank stack pointer to save location
  stx STACK_POINTER_SAVE

  ldx #$ff       ; Initialize stack for new bank 
  txs

  ; Set up stack on new bank for RTI to start routine
  pha            ; Push high order address
  tya            ; Push low order address
  pha
  lda #0
  pha            ; Push 0 to status flags
  pha            ; Push 'A' = 0
  pha            ; Push 'X' = 0
  pha            ; Push 'Y' = 0

  lda STACK_POINTER_SAVE ; first bank stack pointer in A

  ; Save new bank stack pointer to save location
  tsx
  stx STACK_POINTER_SAVE

  ; Restore first bank stack pointer
  tax
  txs

  lda PORTA      ; Switch to first bank
  and #(~BANK & $ff)
  ora #BANK_START
  sta PORTA

  inc FIRST_UNUSED_BANK

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

  ; Increment the memory bank
  lda PORTA
  tay
  and #BANK
  tax
  inx
  cpx FIRST_UNUSED_BANK
  bne no_bank_reset
  ldx #BANK_START
no_bank_reset:
  stx TASK_SWITCH_SCRATCH
  tya
  and #(~BANK & $ff)
  ora TASK_SWITCH_SCRATCH
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
