CLOCK_FREQ_KHZ    = 2000

PORTB = $6000
PORTA = $6001
DDRB  = $6002
DDRA  = $6003

; PORTA assignments
BANK_MASK         = %00001111
MORSE_LED         = %00010000
CONTROL_BUTTON    = %00100000
CONTROL_LED       = %01000000
FLASH_LED         = %10000000

PORTA_OUT_MASK   = BANK_MASK | CONTROL_LED | MORSE_LED | FLASH_LED

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

PORTB_OUT_MASK    = DISPLAY_BITS_MASK | T1_SQWAVE_OUT

  .include display_parameters.inc
  .include musical_notes.inc
  .include 6522.inc

DELAY                  = CLOCK_FREQ_KHZ * 2  ; 1 KHz / 2 = 500 Hz

; Banked zero page supervisor locations starting at $00e0
WAKE_AT                = $e0 ; 2 bytes
SLEEPING               = $e2
STACK_POINTER_SAVE     = $e3

CP_M_BLOCK_P           = $e4 ; 2 bytes
CP_M_DEST_P            = $e6 ; 2 bytes
CP_M_SRC_P             = $e8 ; 2 bytes

; Shared memory locations
TICKS_COUNTER          = $3b00 ; 2 bytes
FIRST_UNUSED_BANK      = $3b02
SCREEN_LOCK            = $3b03
NOTE_PLAYING           = $3b04

BUFFER_READ_POS        = $3cfd
BUFFER_WRITE_POS       = $3cfe
BUFFER_LOCK            = $3cff
BUFFER_DATA            = $3d00    

LED_CONTROL_RELOCATE   = $3800

INTERRUPT_ROUTINE      = $3f00

  .org $2000
  jmp program_entry

  ; Place delay_routines at start of page to ensure no page boundary crossings during timing loops
  .include delay_routines.inc

  .include display_routines.inc
  .include convert_to_hex.inc
  .include musical_notes_tables.inc
  .include utilities.inc
  .include copy_memory_inline.inc
  .include sound.inc
  .include console.inc
  .include buffer.inc
  .include morse.inc

  ; Programs
  .include prg_counters.inc
  .include prg_chase.inc
  .include prg_play_song.inc
  .include prg_ditty.inc
  .include prg_print_ticks_counter.inc
  .include prg_flash_led.inc
  .include prg_led_control.inc
  .include prg_morse_demo.inc
  .include prg_console_demo.inc

program_entry:
  ldx #$ff                                 ; Initialize stack
  txs

  lda #0                                   ; Initialize status flags
  pha
  plp

  ; Initialize 6522 port A (memory banking control)
  lda #BANK_START
  sta PORTA
  lda #PORTA_OUT_MASK                      ; Set pin direction on port A
  sta DDRA

  ; Initialize 6522 port B (display control)
  lda #0
  sta PORTB
  lda #PORTB_OUT_MASK                      ; Set pin direction on port B
  sta DDRB

  ; Set up interrupt handler redirect
  lda #$4c                                 ; jmp
  sta INTERRUPT_ROUTINE
  lda #<interrupt
  sta INTERRUPT_ROUTINE + 1
  lda #>interrupt
  sta INTERRUPT_ROUTINE + 2

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

  lda #<play_ditty
  ldx #>play_ditty
  jsr initialize_additional_process

  lda #<flash_led
  ldx #>flash_led
  jsr initialize_additional_process

;  lda #<print_ticks_counter
;  ldx #>print_ticks_counter
;  jsr initialize_additional_process 

;  lda #<led_control
;  ldx #>led_control
;  jsr initialize_additional_process

  ; Test out relocating a process to another location in RAM
  jsr copy_memory_inline
  .word LED_CONTROL_RELOCATE, led_control, led_control_end - led_control
  lda #<LED_CONTROL_RELOCATE
  ldx #>LED_CONTROL_RELOCATE
  jsr initialize_additional_process

  jsr add_morse_demo

;  jsr add_console_demo

  ; Configure timer 2 to be used for task switching
  lda #0                   ; Timer 2 one shot run mode 
  sta ACR

  ; Start timer 2 (interrupt timer)
  lda #<DELAY
  sta T2CL
  lda #>DELAY
  sta T2CH                 ; Store to high register starts the timer

  lda #(IERSETCLEAR | IT2) ; Enable timer 2 interrupts
  sta IER

  ; For now we need at least one process with a busy loop to ensure not all proceses are sleeping
busy_loop:
  bra busy_loop


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
  pha ; divide millis by 2 (assuming 500 KHz interrupt rate)
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

;  lda #ILED               ; Turn on interrupt activity LED
;  tsb PORTA

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
  and #BANK_MASK
  inc
  cmp FIRST_UNUSED_BANK
  bne switch_to_incoming_bank
  lda #BANK_START         ; We were on the last bank so start over at the first
switch_to_incoming_bank:
  tax
  lda #BANK_MASK
  trb PORTA
  txa
  tsb PORTA               ; Switch to incoming bank

  lda SLEEPING
  beq not_sleeping

  lda WAKE_AT             ; Compare WAKE_AT - TICKS_COUNTER
  cmp TICKS_COUNTER
  lda WAKE_AT + 1
  sbc TICKS_COUNTER + 1
  bpl next_bank           ; Next bank if WAKE_AT > TICKS_COUNTER

  lda #0
  sta SLEEPING            ; Stop sleeping


not_sleeping:
  ldx STACK_POINTER_SAVE ; Restore incoming bank stack pointer from save location
  txs

  inc TICKS_COUNTER       ; Increment the ticks counter
  bne dont_increment_high_ticks
  inc TICKS_COUNTER + 1
dont_increment_high_ticks:
 
  ply                    ; Start restoring incoming bank registers from stack
  plx

;  lda #ILED              ; Turn off interrupt activity LED
;  trb PORTA

  pla                    ; Finish restoring incoming bank registers from stack

  rti                    ; Return to the program in the incoming bank
