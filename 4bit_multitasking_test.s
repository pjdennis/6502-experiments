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

  .include display_parameters.inc
  .include musical_notes.inc
  .include 6522.inc

DELAY       = 2000 ; 2000 microseconds = 2 milliseconds; rate = 500 Hz

BUSY_COUNTER_DELTA     = 1

; Banked memory locations
BUSY_COUNTER           = $0000 ; 2 bytes
BUSY_COUNTER_INCREMENT = $0002 ; 2 bytes
WAKE_AT                = $0004 ; 2 bytes
PLAY_SONG_PARAM        = $0006 ; 2 bytes
MORSE_STRING_PARAM     = $0008 ; 2 bytes
BUSY_COUNTER_LOCATION  = $000A
STACK_POINTER_SAVE     = $000B
TASK_SWITCH_SCRATCH    = $000C
SLEEPING               = $000D

; Shared memory locations
TICKS_COUNTER          = $2000 ; 2 bytes
FIRST_UNUSED_BANK      = $2002
SCREEN_LOCK            = $2003
NOTE_PLAYING           = $2004

  .org $8000

  ; Place code for delay_routines at start of page to ensure no page boundary crossings during timing loops
  .include delay_routines.inc

  .include display_routines.inc
  .include convert_to_hex.inc
  .include musical_notes_tables.inc
  .include utilities.inc
  .include sound.inc

  ; Programs
  .include prg_counters.inc
  .include prg_chase.inc
  .include prg_play_song.inc
  .include prg_ditty.inc
  .include prg_print_ticks_counter.inc
  ;.include prg_flash_led.inc
  .include morse.inc
  .include prg_led_control.inc

reset:
  sei
  ; Disable 6522 interrupts
  lda #(~IERSETCLEAR & $ff) ; Disable all interrupts
  sta IER
  cli

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

  ; Initialize variables
  lda #(BANK_START + 1)
  sta FIRST_UNUSED_BANK

  lda #0
  sta SCREEN_LOCK
  sta NOTE_PLAYING
  sta SLEEPING
  sta TICKS_COUNTER
  sta TICKS_COUNTER + 1

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

  lda #<send_morse_message
  ldx #>send_morse_message
  jsr initialize_additional_process

  lda #<play_ditty
  ldx #>play_ditty
  jsr initialize_additional_process

  lda #<print_ticks_counter
  ldx #>print_ticks_counter
  jsr initialize_additional_process 

  lda #<led_control
  ldx #>led_control
  jsr initialize_additional_process


  ; Configure interrupt timer
  lda #0  ; Timer 2 one shot run mode 
  sta ACR

  ; Start timer 2 (interrupt timer)
  lda #<DELAY
  sta T2CL
  lda #>DELAY
  sta T2CH     ; Store to high register starts the timer

  lda #(IERSETCLEAR | IT2) ; Enable timer 2 interrupts
  sta IER

  ; For now we need at least one process with a busy loop to ensure not all proceses are sleeping
busy_loop:
  bra busy_loop


morse_message:
  .asciiz 'HELLO WORLD THIS IS A COMPUTER BUILT BY PHIL'

send_morse_message:
  lda #<morse_message
  ldx #>morse_message
  jsr send_morse_string

  lda #<2000
  ldx #>2000
  jsr sleep_milliseconds

  bra send_morse_message


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
  txa            ; Save first bank stack pointer to save location
  tsx
  stx STACK_POINTER_SAVE
  tax            ; high order address in X

  lda PORTA      ; Switch to first unused bank
  and #(~BANK_MASK & $ff)
  ora FIRST_UNUSED_BANK
  sta PORTA

  lda #0         ; Task is not sleeping
  sta SLEEPING

  txa            ; high order address in A
  ldx #$ff       ; Initialize stack for new bank 
  txs

  ; Set up stack on new bank for RTI to start routine
  pha            ; Push high order address
  phy            ; Push low order address
  lda #0
  pha            ; Push 0 to status flags
  pha            ; Push 'A' = 0
  pha            ; Push 'X' = 0
  pha            ; Push 'Y' = 0

  ; Save new bank stack pointer to save location
  tsx
  stx STACK_POINTER_SAVE

  lda PORTA      ; Switch to first bank
  and #(~BANK_MASK & $ff)
  ora #BANK_START
  sta PORTA

  ; Restore first bank stack pointer
  ldx STACK_POINTER_SAVE
  txs

  inc FIRST_UNUSED_BANK

  rts


;On entry A = Sleep count low
;         X = Sleep count high
;On exit  X,Y preserved
;         A not preserved
sleep_milliseconds:
  phx
  pha ; divide millis by 2 (assuming DELAY = 500)
  txa
  lsr
  tax
  pla
  ror
  jsr sleep
  plx
  rts


;On entry A = Sleep count low
;         X = Sleep count high
;On exit  X, Y preserved
;         A not preserved
sleep:
  sei
  clc
  adc TICKS_COUNTER
  sta WAKE_AT
  txa
  adc TICKS_COUNTER + 1
  sta WAKE_AT + 1
  lda #1
  sta SLEEPING
  cli
sleep1:
  lda SLEEPING
  bne sleep1
  rts


; Interrupt handler - switch memory banks and routines
interrupt:
  pha                     ; Start saving outgoing bank registers to stack

  jsr interrupt_led_on    ; (Turn on the interrupt activity LED)

  lda #<DELAY             ; (Reset 6552 timer to trigger next interrupt)
  sta T2CL
  lda #>DELAY
  sta T2CH                ; (Store to the high register starts the timer and clears interrupt)
  
  phx                     ; Finish saving outgoing bank registers to stack
  phy

  tsx                     ; Save outgoing bank stack pointer to save location
  stx STACK_POINTER_SAVE

next_bank:  
  lda PORTA               ; Increment the memory bank
  tay
  and #BANK_MASK
  tax
  inx
  cpx FIRST_UNUSED_BANK
  bne switch_to_incoming_bank
  ldx #BANK_START         ; We were on the last bank so start over at the first
switch_to_incoming_bank:
  stx TASK_SWITCH_SCRATCH ; Switch to incoming bank
  tya                     ; Original value of PORTA
  and #(~BANK_MASK & $ff)
  ora TASK_SWITCH_SCRATCH
  sta PORTA

  lda SLEEPING
  beq not_sleeping

  lda WAKE_AT             ; Compare WAKE_AT - TICKS_COUNTER
  cmp TICKS_COUNTER
  lda WAKE_AT + 1
  sbc TICKS_COUNTER + 1
  bpl next_bank           ; Next bank if WAKE_AT > TICKS_COUNTER

  lda #0
  sta SLEEPING         ; Stop sleeping

not_sleeping:
  ldx STACK_POINTER_SAVE ; Restore incoming bank stack pointer from save location
  txs

  inc TICKS_COUNTER       ; Increment the ticks counter
  bne dont_increment_high_ticks
  inc TICKS_COUNTER + 1
dont_increment_high_ticks:
 
  ply                    ; Start restoring incoming bank registers from stack
  plx

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
