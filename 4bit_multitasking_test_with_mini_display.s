  .include base_config_v1.inc

; PORTA assignments
MORSE_LED         = %00010000
CONTROL_BUTTON    = %00100000
CONTROL_LED       = %01000000

PORTA_OUT_MASK    = BANK_MASK | CONTROL_LED | MORSE_LED | SD_CSB

SD_DATA           = %00001000
SD_CLK            = %00010000
SD_DC             = %00100000
SD_CS_PORT        = PORTA
SD_DATA_PORT      = PORTB

; PORTB assignments
T1_SQWAVE_OUT     = %10000000

PORTB_OUT_MASK    = DISPLAY_BITS_MASK | T1_SQWAVE_OUT

  .include musical_notes.inc

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
BANK_TEMP              = $3b05

BUFFER_READ_POS        = $3cfd
BUFFER_WRITE_POS       = $3cfe
BUFFER_LOCK            = $3cff
BUFFER_DATA            = $3d00    

  .org $2000
  jmp program_entry

  ; Place delay_routines at start of page to ensure no page boundary crossings during timing loops
  .include delay_routines.inc

  .include display_routines_4bit.inc
  .include display_hex.inc
  .include musical_notes_tables.inc
  .include utilities.inc
  .include copy_memory_inline.inc
  .include sound.inc
  .include console.inc
  .include buffer.inc
  .include morse.inc
  .include character_patterns_6x8.inc

  ; Programs
  .include prg_counters.inc
  .include prg_chase.inc
  .include prg_play_song.inc
  .include prg_ditty.inc
  .include prg_print_ticks_counter.inc
  .include prg_led_control.inc
  .include prg_morse_demo.inc
  .include prg_small_display_demo.inc

program_entry:
  ldx #$ff                                 ; Initialize stack
  txs

  lda #0                                   ; Initialize status flags
  pha
  plp

  ; Initialize 6522 port A (memory banking control)
  lda #(BANK_START | SD_CSB)
  sta PORTA
  lda #PORTA_OUT_MASK                      ; Set pin direction on port A
  sta DDRA

  ; Initialize 6522 port B (display control)
  lda #0
  sta PORTB
  lda #PORTB_OUT_MASK                      ; Set pin direction on port B
  sta DDRB

  ; Set up the RAM vector pull location
  lda #<interrupt
  sta $3ffe
  lda #>interrupt
  sta $3fff

  ; Initialize variables
  lda #(BANK_START + 1)
  sta FIRST_UNUSED_BANK

  stz SCREEN_LOCK
  stz NOTE_PLAYING
  stz SLEEPING
  stz TICKS_COUNTER
  stz TICKS_COUNTER + 1

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

  lda #<led_control
  ldx #>led_control
  jsr initialize_additional_process

  jsr add_morse_demo

  lda #<mini_display_demo
  ldx #>mini_display_demo
  jsr initialize_additional_process 

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

  ; TEMPORARY
  ; jmp mini_display_demo

busy_loop:
  lda #<100
  ldx #>100
  jsr sleep_milliseconds
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

  stz SLEEPING   ; Task is not sleeping

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
  phy
  pha ; divide millis by 2 (assuming 500 KHz interrupt rate)
  txa
  lsr
  tax
  pla
  ror
  jsr sleep
  ply
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
  inc SLEEPING
  bra switch_to_next_bank


; Interrupt handler - switch memory banks and routines
interrupt:
  pha                     ; Start saving outgoing bank registers to stack

  lda #<DELAY             ; (Reset 6552 timer to trigger next interrupt)
  sta T2CL
  lda #>DELAY
  sta T2CH                ; (Store to the high register starts the timer and clears interrupt)

  phx                     ; Finish saving outgoing bank registers to stack
  phy

  inc TICKS_COUNTER       ; Increment the ticks counter
  bne interrupt_high_ticks_ok
  inc TICKS_COUNTER + 1
interrupt_high_ticks_ok:

switch_to_next_bank:
  tsx                     ; Save outgoing bank stack pointer to save location
  stx STACK_POINTER_SAVE

find_next_bank:
  lda PORTA
  and #BANK_MASK
  sta BANK_TEMP

next_bank:  
  inc                     ; Increment the memory bank
  cmp FIRST_UNUSED_BANK
  bne interrupt_bank_ok
  lda #BANK_START         ; We were on the last bank so start over at the first
interrupt_bank_ok:
  tax
  lda #BANK_MASK
  trb PORTA
  txa
  tsb PORTA               ; Switch to incoming bank

  lda SLEEPING
  beq not_sleeping        ; Branch if not sleeping

  lda WAKE_AT             ; Compare WAKE_AT - TICKS_COUNTER
  cmp TICKS_COUNTER
  lda WAKE_AT + 1
  sbc TICKS_COUNTER + 1
  bmi stop_sleeping       ; Stop sleeping if WAKE_AT <= TICKS_COUNTER

  lda PORTA
  and #BANK_MASK
  cmp BANK_TEMP
  bne next_bank

  ; Everything is sleeping
  wai

  lda #<DELAY             ; (Reset 6552 timer to trigger next interrupt)
  sta T2CL
  lda #>DELAY
  sta T2CH                ; (Store to the high register starts the timer and clears interrupt)

  inc TICKS_COUNTER       ; Increment the ticks counter
  bne interrupt_high_ticks_ok2
  inc TICKS_COUNTER + 1
interrupt_high_ticks_ok2:

  bra find_next_bank

stop_sleeping:
  stz SLEEPING            ; Stop sleeping

  ldx STACK_POINTER_SAVE
  txs
  cli
  rts

not_sleeping:
  ldx STACK_POINTER_SAVE ; Restore incoming bank stack pointer from save location
  txs

  ply                    ; Restore incoming bank registers from stack
  plx
  pla

  rti                    ; Return to the program in the incoming bank
