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
FLASH_LED         = %10000000

; PORTB assignments
DISPLAY_DATA_MASK = %01111000
E                 = %00000100
RW                = %00000010
RS                = %00000001
BF                = %01000000
T1_SQWAVE_OUT     = %10000000
DISPLAY_BITS_MASK = (DISPLAY_DATA_MASK | E | RW | RS)

  .include display_parameters.inc
  .include musical_notes.inc

; 6522 timer registers
T1CL = $6004
T1CH = $6005
T1LL = $6006
T1LH = $6007
T2CL = $6008
T2CH = $6009
ACR  = $600B
IFR  = $600D
IER  = $600E

ACR_T1_CONT_SQWAVE = %11000000

; 6522 timer flag masks
IERSETCLEAR = %10000000
IT1         = %01000000
IT2         = %00100000

DELAY      = 2000 ; 2000 microseconds = 2 milliseconds; rate = 500 Hz
NOTE_DELAY = NOTE_C4

BUSY_COUNTER_DELTA     = 1

; Banked memory locations
BUSY_COUNTER           = $0000 ; 2 bytes
BUSY_COUNTER_INCREMENT = $0002 ; 2 bytes
BUSY_COUNTER_LOCATION  = $0004
STACK_POINTER_SAVE     = $0005
DISPLAY_SCRATCH        = $0006
TASK_SWITCH_SCRATCH    = $0007
NOTE_PLAYING           = $0008

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
  lda #(BANK | LED | ILED | FLASH_LED) ; Set pin direction  on port A
  sta DDRA

  ; Initialize 6522 port B (display control)
  lda #0
  sta PORTB
  lda #(DISPLAY_BITS_MASK | T1_SQWAVE_OUT) ; Set display pins and T1 output pins to output
  sta DDRB

  ; Initialize process control area
  lda #(BANK_START + 1)
  sta FIRST_UNUSED_BANK

  lda #0
  sta SCREEN_LOCK
  sta NOTE_PLAYING

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

  lda #<play_music
  ldx #>play_music
  jsr initialize_additional_process


  ; Configure timers
  lda #0  ; Timer 2 one shot run mode 
  sta ACR
  lda #(IERSETCLEAR | IT2) ; Enable timer 2 interrupts
  sta IER

  ; Start timer 2 (interrupt timer)
  lda #<DELAY
  sta T2CL
  lda #>DELAY
  sta T2CH     ; Store to high register starts the timer


  ; Start the main routine
  jmp led_control


play_music:
  ldx #NOTE_IDX_C4
music_loop_up:
  txa
  pha
  jsr start_note
  jsr delay_tenth
  pla
  tax
  inx
  cpx #(NOTE_IDX_C5 + 1)
  bne music_loop_up

  ldx #NOTE_IDX_B4
music_loop_down:
  txa
  pha
  jsr start_note
  jsr delay_tenth
  pla
  tax
  dex
  cpx #(NOTE_IDX_C4 - 1)
  bne music_loop_down

  jsr stop_note
  jsr delay_tenth

  jmp play_music


; On entry A = index of note
start_note:
  asl
  tay
  lda NOTE_PLAYING
  beq first_note
  ; not the first note
  lda notes,Y
  sta T1LL
  lda notes + 1,Y
  sta T1LH
  rts
first_note:
  lda #ACR_T1_CONT_SQWAVE  ; Enable timer 1 continuous square wave
  sta ACR

  lda notes,Y
  sta T1CL
  lda notes + 1,Y
  sta T1CH                 ; Starts the timer
  lda #1
  sta NOTE_PLAYING
  rts


stop_note:
  lda #0
  sta ACR
  STA T1CL
  STA T1CH
  sta NOTE_PLAYING
  rts

notes:
  .word NOTE_C4  
  .word NOTE_CS4
  .word NOTE_D4 
  .word NOTE_DS4
  .word NOTE_E4	
  .word NOTE_F4	
  .word NOTE_FS4
  .word NOTE_G4	
  .word NOTE_GS4
  .word NOTE_A4 
  .word NOTE_AS4
  .word NOTE_B4 
  .word NOTE_C5

; Routine will flash an LED using busy wait for delay
flash_led:
  sei
  lda PORTA
  ora #FLASH_LED
  sta PORTA
  cli

  jsr delay_tenth

  sei
  lda PORTA
  and #(~FLASH_LED & $ff)
  sta PORTA
  cli

  jsr delay_tenth
  
  jmp flash_led


delay_tenth:
  lda #200
  jsr delay_10_thousandths
  jsr delay_10_thousandths   
  ;jsr delay_10_thousandths   
  ;jsr delay_10_thousandths   
  ;jsr delay_10_thousandths   
  rts


led_control:
  lda PORTA
  and #BUTTON1
  bne led_control
  ; Button down; toggle LED state
  sei
  lda PORTA
  eor #LED
  sta PORTA
  cli

led_wait_button:
  ldx #10
led_wait_button_outer:
  ldy #30
led_wait_button_inner:
  lda PORTA
  and #BUTTON1
  beq led_wait_button
  dey
  bne led_wait_button_inner
  dex
  bne led_wait_button_outer

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
  pha                     ; Start saving outgoing bank registers to stack

  jsr interrupt_led_on    ; (Turn on the interrupt activity LED)

  lda #<DELAY             ; (Reset 6552 timer to trigger next interrupt)
  sta T2CL
  lda #>DELAY
  sta T2CH                ; (Store to the high register starts the timer and clears interrupt)
  
  txa                     ; Finish saving outgoing bank registers to stack
  pha
  tya
  pha

  tsx                     ; Save outgoing bank stack pointer to save location
  stx STACK_POINTER_SAVE
  
  lda PORTA               ; Increment the memory bank
  tay
  and #BANK
  tax
  inx
  cpx FIRST_UNUSED_BANK
  bne switch_to_incoming_bank
  ldx #BANK_START         ; We were on the last bank so start over at the first
switch_to_incoming_bank:
  stx TASK_SWITCH_SCRATCH ; Switch to incoming bank
  tya
  and #(~BANK & $ff)
  ora TASK_SWITCH_SCRATCH
  sta PORTA
  
  ldx STACK_POINTER_SAVE ; Restore incoming bank stack pointer from save location
  txs
 
  pla                    ; Start restoring incoming bank registers from stack
  tay
  pla
  tax

  jsr interrupt_led_off  ; (Turn off interrupt activity LED)

  pla                    ; Finish restoring incoming bank registers from stack

  rti                    ; Return to the program in the incoming bank


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
