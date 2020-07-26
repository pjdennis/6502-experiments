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

;DELAY      = 2000 ; 2000 microseconds = 2 milliseconds; rate = 500 Hz
DELAY       = 1000 ; 1000 microseconds = 1 milliseconds; rate = 1000 Hz
DELAY_DIV   = (DELAY / 1000)

BUSY_COUNTER_DELTA     = 1

; Banked memory locations
BUSY_COUNTER           = $0000 ; 2 bytes
BUSY_COUNTER_INCREMENT = $0002 ; 2 bytes
WAKE_AT                = $0004 ; 2 bytes
PLAY_SONG_PARAM        = $0006 ; 2 bytes
BUSY_COUNTER_LOCATION  = $0008
STACK_POINTER_SAVE     = $0009
DISPLAY_SCRATCH        = $000A
TASK_SWITCH_SCRATCH    = $000B
SLEEPING               = $000C

; Shared memory locations
TICKS_COUNTER          = $2000 ; 2 bytes
FIRST_UNUSED_BANK      = $2002
SCREEN_LOCK            = $2003
NOTE_PLAYING           = $2004

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

  lda #<flash_led_sleep
  ldx #>flash_led_sleep
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


  ; For now we need at least one process with a busy loop to ensure not all proceses are sleeping
busy_loop:
  bra busy_loop


play_ditty:
  lda #<ditty
  ldx #>ditty
  jmp play_song ; tail call


play_song:
  sta PLAY_SONG_PARAM
replay_song:
  phx
  stx PLAY_SONG_PARAM + 1
  ldy #0                   ; Music position counter
song_loop:
  lda (PLAY_SONG_PARAM),Y
  cmp #NOTE_IDX_NULL
  beq done_with_song
  cmp #NOTE_IDX_REST
  beq song_rest
  jsr start_note
  bra song_delay
song_rest:
  jsr stop_note
song_delay:
  iny
  lda (PLAY_SONG_PARAM),Y
  asl
  phy
  tay
  lda durations,Y
  ldx durations + 1,Y
  ply
  jsr sleep_milliseconds
  iny
  bne song_loop
  ; increment the song param high byte
  inc PLAY_SONG_PARAM + 1
  bra song_loop
done_with_song:
  jsr stop_note
  lda #<1000
  ldx #>1000
  jsr sleep_milliseconds
  plx
  bra replay_song 


play_chromatic_scale:
  ldy #NOTE_IDX_C4
scale_loop_up:
  tya
  jsr start_note
  
  lda #<500
  ldx #>500
  jsr sleep_milliseconds

  iny
  cpy #(NOTE_IDX_C5 + 1)
  bne scale_loop_up

  ldy #NOTE_IDX_B4
scale_loop_down:
  tya
  jsr start_note

  lda #<500
  ldx #>500
  jsr sleep_milliseconds

  dey
  cpy #(NOTE_IDX_C4 - 1)
  bne scale_loop_down

  jsr stop_note
  
  lda #<1500
  ldx #>1500
  jsr sleep_milliseconds

  bra play_chromatic_scale


; On entry A = index of note
; On exit  X, Y are preserved
;          A is not preserved
start_note:
  phy
  asl
  tay
  lda NOTE_PLAYING
  beq first_note
  ; not the first note
  lda notes,Y
  sta T1LL
  lda notes + 1,Y
  sta T1LH
  bra start_note_done
first_note:
  lda #ACR_T1_CONT_SQWAVE  ; Enable timer 1 continuous square wave
  sta ACR

  lda notes,Y
  sta T1CL
  lda notes + 1,Y
  sta T1CH                 ; Starts the timer
  lda #1
  sta NOTE_PLAYING
start_note_done:
  ply
  rts


stop_note:
  lda NOTE_PLAYING
  beq note_stopped
  lda #0
  sta ACR
  STA T1CL
  STA T1CH
  sta NOTE_PLAYING
note_stopped:
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

durations:
  .word 1000 ; SEMIBREVE
  .word  500 ; MINIM
  .word  250 ; CROTCHET
  .word  125 ; QUAVER
  .word   62 ; SEMIQUAVER


ditty:
  .byte NOTE_IDX_C4,   DURATION_SEMIBREVE 

  .byte NOTE_IDX_E4,   DURATION_SEMIBREVE

  .byte NOTE_IDX_G4,   DURATION_QUAVER
  .byte NOTE_IDX_REST, DURATION_QUAVER
  .byte NOTE_IDX_REST, DURATION_QUAVER
  .byte NOTE_IDX_F4,   DURATION_QUAVER
  .byte NOTE_IDX_E4,   DURATION_CROTCHET
  .byte NOTE_IDX_D4,   DURATION_CROTCHET

  .byte NOTE_IDX_C4,   DURATION_SEMIBREVE

  .byte NOTE_IDX_A4,   DURATION_QUAVER
  .byte NOTE_IDX_G4,   DURATION_QUAVER
  .byte NOTE_IDX_A4,   DURATION_QUAVER
  .byte NOTE_IDX_G4,   DURATION_QUAVER
  .byte NOTE_IDX_A4,   DURATION_QUAVER
  .byte NOTE_IDX_G4,   DURATION_QUAVER
  .byte NOTE_IDX_F4,   DURATION_QUAVER
  .byte NOTE_IDX_E4,   DURATION_QUAVER

  .byte NOTE_IDX_G4,   DURATION_QUAVER
  .byte NOTE_IDX_F4,   DURATION_QUAVER
  .byte NOTE_IDX_G4,   DURATION_QUAVER
  .byte NOTE_IDX_F4,   DURATION_QUAVER
  .byte NOTE_IDX_G4,   DURATION_QUAVER
  .byte NOTE_IDX_F4,   DURATION_QUAVER
  .byte NOTE_IDX_E4,   DURATION_QUAVER
  .byte NOTE_IDX_D4,   DURATION_QUAVER

  .byte NOTE_IDX_E4,   DURATION_QUAVER
  .byte NOTE_IDX_D4,   DURATION_QUAVER
  .byte NOTE_IDX_E4,   DURATION_QUAVER
  .byte NOTE_IDX_F4,   DURATION_QUAVER
  .byte NOTE_IDX_E4,   DURATION_CROTCHET
  .byte NOTE_IDX_D4,   DURATION_CROTCHET

  .byte NOTE_IDX_C4,   DURATION_SEMIBREVE

  .byte NOTE_IDX_NULL


print_ticks_counter:
  jsr lock_screen

  lda #(DISPLAY_SECOND_LINE + 6)
  jsr move_cursor

  sei
  lda TICKS_COUNTER
  pha
  lda TICKS_COUNTER + 1
  cli

  jsr display_hex
  pla
  jsr display_hex

  jsr unlock_screen

  jsr delay_tenth

  bra print_ticks_counter


; Routine will flash an LED using busy wait for delay
flash_led_sleep:
  sei
  lda PORTA
  eor #FLASH_LED
  sta PORTA
  cli

  lda #<300
  ldx #>300
  jsr sleep_milliseconds
  
  bra flash_led_sleep


delay_tenth:
  pha
  phx

  lda #100
  ldx #0
  jsr sleep_milliseconds

  plx
  pla
  rts


led_control:
  lda PORTA
  and #BUTTON1
  beq button_down

  lda #<50
  ldx #>50
  jsr sleep_milliseconds

  bra led_control
button_down:
  sei
  lda PORTA
  eor #LED
  sta PORTA
  cli
led_wait_button:
  ldy #5
led_wait_button_loop:
  lda #<10
  ldx #>10
  jsr sleep_milliseconds

  lda PORTA
  and #BUTTON1
  beq led_wait_button
  
  dey
  bne led_wait_button_loop

  bra led_control


; Busy loop incrementing and displaying counter
run_counter_top_left:
  lda #BUSY_COUNTER_DELTA
  ldx #(DISPLAY_FIRST_LINE + 0)
  bra run_counter

; Busy loop incrementing and displaying counter
run_counter_top_right:
  lda #(-BUSY_COUNTER_DELTA)
  ldx #(DISPLAY_FIRST_LINE + 12)
  bra run_counter

; Busy loop incrementing and displaying counter
run_counter_bottom_left:
  lda #(-BUSY_COUNTER_DELTA)
  ldx #(DISPLAY_SECOND_LINE + 0)
  bra run_counter

; Busy loop incrementing and displaying counter
run_counter_bottom_right:
  lda #BUSY_COUNTER_DELTA
  ldx #(DISPLAY_SECOND_LINE + 12)
  bra run_counter

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
  jsr move_cursor

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

  lda #<100
  ldx #>100
  jsr sleep_milliseconds

  bra run_counter_repeat


run_chase:
  ldy #(DISPLAY_FIRST_LINE + 5)
run_chase_right:
  jsr lock_screen
  tya
  jsr move_cursor
  lda #' '
  jsr display_character
  lda #'X'
  jsr display_character
  jsr unlock_screen

  lda #<(150 / DELAY_DIV)
  ldx #>(150 / DELAY_DIV)
  jsr sleep

  iny
  cpy #(DISPLAY_FIRST_LINE + 10)
  bne run_chase_right

  ldy #(DISPLAY_FIRST_LINE + 9)
run_chase_left:
  jsr lock_screen
  tya
  jsr move_cursor
  lda #'X'
  jsr display_character
  lda #' '
  jsr display_character
  jsr unlock_screen

  lda #<(150 / DELAY_DIV)
  ldx #>(150 / DELAY_DIV)
  jsr sleep

  dey
  cpy #(DISPLAY_FIRST_LINE + 4)
  bne run_chase_left

  bra run_chase
  

lock_screen:
  sei
  lda SCREEN_LOCK
  beq lock_acquired
  cli
  bra lock_screen
lock_acquired:
  inc SCREEN_LOCK
  cli
  rts


unlock_screen:
  lda #0
  sta SCREEN_LOCK
  rts

display_hex:
  jsr convert_to_hex
  jsr display_character
  txa
  jmp display_character ; tail call


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

  ldx #0         ; Task is not sleeping
  sta SLEEPING

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


;On entry A = Sleep count low
;         X = Sleep count high
;On exit  X,Y preserved
;         A not preserved
sleep_milliseconds:
;  pha ; divide millis by 2 (assuming DELAY = 500)
;  txa
;  lsr
;  tax
;  pla
;  ror
  jmp sleep ; tail call

;On entry A = Sleep count low
;         X = Sleep count high
;On exit  Y,X preserved
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
  and #BANK
  tax
  inx
  cpx FIRST_UNUSED_BANK
  bne switch_to_incoming_bank
  ldx #BANK_START         ; We were on the last bank so start over at the first
switch_to_incoming_bank:
  stx TASK_SWITCH_SCRATCH ; Switch to incoming bank
  tya                     ; Original value of PORTA
  and #(~BANK & $ff)
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
