PORTB = $6000
PORTA = $6001
DDRB = $6002
DDRA = $6003

; 6522 timer registers
T1CL = $6004
T1CH = $6005
ACR = $600B
IFR = $600D
IER = $600E

; 6522 timer flag masks
IERSETCLEAR = %10000000
IT1 = %01000000

; PORTA assignments
BUTTON1           = %10000000
BUTTON2           = %01000000
ILED              = %00100000
LED               = %00010000
BANK              = %00001111

BANK_A            = %0100
BANK_B            = %0101

BANK_START        = %00000100
BANK_STOP         = %00010000

; PORTB assignments
DISPLAY_DATA_MASK = %11110000
BF                = %10000000

E                 = %00001000
RW                = %00000100
RS                = %00000010

DISPLAY_BITS_MASK = (DISPLAY_DATA_MASK | E | RW | RS)

CMD_CLEAR_DISPLAY           = %00000001
CMD_RETURN_HOME             = %00000010
CMD_ENTRY_MODE_SET          = %00000100
CMD_DISPLAY_ON_OFF_CONTROL  = %00001000
CMD_CURSOR_OR_DISPLAY_SHIFT = %00010000
CMD_FUNCTION_SET            = %00100000
CMD_SET_CGRAM_ADDRESS       = %01000000
CMD_SET_DDRAM_ADDRESS       = %10000000

DISPLAY_FIRST_LINE  = $00
DISPLAY_SECOND_LINE = $40

; Memory locations

TEST_PARAM             = $0000
DISPLAY_STRING_PARAM   = $0004
CREATE_CHARACTER_PARAM = $0002

INTERRUPT_COUNTER      = $0012
BUSY_COUNTER           = $0014

BANK_TEST_CHAR         = $0020
BANK_TEST_CHAR_FIXED   = $2020
STACK_POINTER_SAVE     = $0021
BANK_SWITCH_SCRATCH    = $0022


; Character definitions
CHARACTER_PD = 0
CHARACTER_ANGEL = 1

DELAY = 1000 ; 1 MHZ cycles

  .org $8000

character_t:
  .byte 'Q'

string_foo:
  .asciiz "Foo"

reset:
  ldx #$ff ; Initialize stack
  txs

  lda #0   ; Initialize status flags
  pha
  plp

  ; Initialize 6522 ports
  lda #BANK_A
  sta PORTA
  lda #(BANK | LED | ILED) ; Set pin direction  on port A
  sta DDRA

  lda #0
  sta PORTB
  lda #DISPLAY_BITS_MASK ; Set display control pins and data pins on port B to output
  sta DDRB


  ; Initialize display
  jsr reset_display
  lda #(CMD_ENTRY_MODE_SET | %10)          ; Increment and shift cursor; don't shift display 
  jsr display_command

  lda #(CMD_DISPLAY_ON_OFF_CONTROL | %100) ; Display on; cursor off; blink off 
  jsr display_command


  jmp skip_create_characters

  ; Create characters
  lda #<character_pd
  ldx #>character_pd
  ldy #CHARACTER_PD
  jsr create_character

  lda #<character_angel
  ldx #>character_angel
  ldy #CHARACTER_ANGEL
  jsr create_character

skip_create_characters:

  ; Display some stuff
  lda #(CMD_SET_DDRAM_ADDRESS | DISPLAY_FIRST_LINE) ; Move to first line
  jsr display_command

  ; Display message 1
  ;lda #<message1
  ;ldx #>message1
  ;jsr display_string


  jmp skip_write_stuff

  lda #'X'
  jsr display_character

  lda #'Y'
  sta DISPLAY_STRING_PARAM
  lda #'Z'
  sta DISPLAY_STRING_PARAM + 1

  lda DISPLAY_STRING_PARAM
  jsr display_character

  lda DISPLAY_STRING_PARAM + 1
  jsr display_character

  lda #<(character_t - 1)
  sta DISPLAY_STRING_PARAM
  lda #>(character_t - 1)
  sta DISPLAY_STRING_PARAM + 1
  ldy #1
  lda (DISPLAY_STRING_PARAM),Y
  jsr display_character


  lda #>string_foo
  jsr convert_to_hex
  jsr display_character
  txa
  jsr display_character

  lda #<string_foo
  jsr convert_to_hex
  jsr display_character
  txa
  jsr display_character

  lda #<string_foo
  sta TEST_PARAM
  lda #>string_foo
  sta TEST_PARAM + 1
;  ldy #0
;  lda (TEST_PARAM),Y
  lda #'X'
  jsr test_routine

  lda TEST_PARAM + 1

  jsr convert_to_hex
  jsr display_character
  lda TEST_PARAM
  pha
  txa
  jsr display_character

  pla
  jsr convert_to_hex
  jsr display_character
  txa
  jsr display_character


skip_write_stuff:

;  lda #<string_foo
;  ldx #>string_foo
;  jsr display_string



  jmp skip_bank_switching

  ; Test out the bank switching
  ; store 'A' into bank 0
  ldx #'A'
  stx BANK_TEST_CHAR

  ; store 'B' into bank 1
  ldx #'B'
  sei
  lda PORTA
  ora #BANK
  sta PORTA
  stx BANK_TEST_CHAR
  and #(~BANK & $ff)
  sta PORTA
  cli

  ; display from bank 0
  lda BANK_TEST_CHAR
  jsr display_character

  ; retrieve from bank 1
  sei
  lda PORTA
  ora #BANK
  sta PORTA
  ldx BANK_TEST_CHAR
  and #(~BANK & $ff)
  sta PORTA
  cli
  txa

  ; display the characer retrieved from bank 1
  jsr display_character

skip_bank_switching:



  ; Store 'Ambidextrous' across the banks
  ldx #BANK_START
  lda #'A'
  jsr store_in_bank

  inx
  lda #'m'
  jsr store_in_bank

  inx
  lda #'b'
  jsr store_in_bank

  inx
  lda #'i'
  jsr store_in_bank

  inx
  lda #'d'
  jsr store_in_bank

  inx
  lda #'e'
  jsr store_in_bank

  inx
  lda #'x'
  jsr store_in_bank

  inx
  lda #'t'
  jsr store_in_bank

  inx
  lda #'r'
  jsr store_in_bank

  inx
  lda #'o'
  jsr store_in_bank

  inx
  lda #'u'
  jsr store_in_bank

  inx
  lda #'s'
  jsr store_in_bank

  ; Retrieve and print from the banks
  ldx #BANK_START
bank_print_loop:
  jsr retrieve_from_bank
  jsr display_character

  inx
  cpx #BANK_STOP
  bne bank_print_loop




  ; Display more stuff
  lda #(CMD_SET_DDRAM_ADDRESS | DISPLAY_SECOND_LINE) ; Move to second line
  jsr display_command


;  lda #CHARACTER_PD     ; Custom character graphic 'PD'
;  jsr display_character 

;  lda #' '
;  jsr display_character

;  lda #%10111100        ; Japanese character
;  jsr display_character

;  lda #' '
;  jsr display_character

;  lda #CHARACTER_ANGEL  ; Custom character graphic 'Angel'
;  jsr display_character

;  lda #' '
;  jsr display_character

  ; display a hex number
;  lda #$a2
;  jsr convert_to_hex
;  jsr display_character
;  txa
;  jsr display_character

;  lda #$92
;  jsr convert_to_hex
;  jsr display_character
;  txa
;  jsr display_character


;  HERE

  lda #'A'
  sta BANK_TEST_CHAR_FIXED

  ldx #BANK_START
bank_fixed_loop:
  jsr bank_fixed_test
  jsr display_character
  inx
  cpx #BANK_STOP
  bne bank_fixed_loop


  ; Skip second process and interrupts
  jmp run_counter

  ; Configure the second process
  lda #<led_control
  ldx #>led_control
  jsr initialize_second_process


  ; Start the interrupt timer

  ; initialize counter to 0
  lda #0
  sta INTERRUPT_COUNTER
  sta INTERRUPT_COUNTER + 1

  ; configure timer
  lda #%01000000 ; Timer 1 free run mode 
  sta ACR
  lda #(IERSETCLEAR | IT1)
  sta IER

  ; set timer delay which starts timer as a side effect
  lda #<DELAY
  sta T1CL
  lda #>DELAY
  sta T1CH     ; store to the high register starts the timer


  ; Start the main routine
  jmp run_counter

; On entry X = bank to test
; On exit  A = value retrieved from bank
bank_fixed_test
  stx BANK_SWITCH_SCRATCH

  sei
  lda PORTA
  tax
  and #(~BANK & $ff)
  ora BANK_SWITCH_SCRATCH
  ; new bank in A; old bank in X; value in Y
  sta PORTA
  nop ; might not need these
  nop
  nop
  nop
  ldy BANK_TEST_CHAR_FIXED
  tya
  iny
  sty BANK_TEST_CHAR_FIXED
  stx PORTA
  nop ; might not need these
  nop
  nop
  nop
  cli
  ldx BANK_SWITCH_SCRATCH

  rts


; On entry A = value to store
;          X = bank to store in
; On exit  X is preserved
store_in_bank:
  stx BANK_SWITCH_SCRATCH
  tay

  sei
  lda PORTA
  tax
  and #(~BANK & $ff)
  ora BANK_SWITCH_SCRATCH
  ; new bank in A; old bank in X; value in Y
  sta PORTA
  nop ; might not need these
  nop
  nop
  nop
  sty BANK_TEST_CHAR
  stx PORTA
  nop ; might not need these
  nop
  nop
  nop
  cli
  ldx BANK_SWITCH_SCRATCH

  rts


; On entry X = bank to retrieve from
; On exit  A = value retrieved
;          X is preserved
retrieve_from_bank:
  stx BANK_SWITCH_SCRATCH

  sei
  lda PORTA
  tax
  and #(~BANK & $ff)
  ora BANK_SWITCH_SCRATCH
  ; new bank in A; old bank in X; load value to Y
  sta PORTA
  nop ; might not need these
  nop
  nop
  nop
  ldy BANK_TEST_CHAR
  stx PORTA
  nop ; might not need these
  nop
  nop
  nop
  cli

  ldx BANK_SWITCH_SCRATCH
  tya
  
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
  lda #(CMD_SET_DDRAM_ADDRESS | (DISPLAY_SECOND_LINE + 12 + 2))
  jsr display_command

  lda BUSY_COUNTER + 1
  jsr convert_to_hex
  jsr display_character
  txa
  jsr display_character

;  lda BUSY_COUNTER
;  jsr convert_to_hex
;  jsr display_character
;  txa
;  jsr display_character

  inc BUSY_COUNTER
  bne run_counter_repeat
  inc BUSY_COUNTER + 1
  jmp run_counter_repeat


; Increment interrupt counter (currently not used)
increment_interrupt_counter:
  inc INTERRUPT_COUNTER
  bne interrupt_inc_done
  inc INTERRUPT_COUNTER + 1
interrupt_inc_done:
  rts


; Repeatedly read and print interrupt counter value (currently not used)
display_interrupt_counter:
  lda #(CMD_SET_DDRAM_ADDRESS | (DISPLAY_SECOND_LINE + 11))
  jsr display_command

  sei
  lda INTERRUPT_COUNTER
  pha
  lda INTERRUPT_COUNTER + 1
  cli

  jsr convert_to_hex
  jsr display_character
  txa
  jsr display_character

  pla
  jsr convert_to_hex
  jsr display_character
  txa
  jsr display_character

  jmp display_interrupt_counter


; Set up stack, etc. so that second process will start running on next interrupt
; On entry A = low source address
;          X = high byte source address
initialize_second_process:
  tay            ; low order address in Y

  lda PORTA      ; Switch to bank 1
  ora #BANK
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
  and #(~BANK & $ff)
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
  eor #BANK
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


message1:
  .asciiz "Hello, World! "


reset_display:
  ; Reset sequence per datasheet

  lda #150
  jsr delay_10_thousandths

  lda #(CMD_FUNCTION_SET | %10000)         ; Set 8-bit mode
  jsr display_command_8bit_no_wait

  lda #41
  jsr delay_10_thousandths

  lda #(CMD_FUNCTION_SET | %10000)         ; Set 8-bit mode
  jsr display_command_8bit_no_wait

  lda #1
  jsr delay_10_thousandths

  lda #(CMD_FUNCTION_SET | %10000)         ; Set 8-bit mode
  jsr display_command_8bit_no_wait

  jsr wait_for_not_busy_8bit

  lda #CMD_FUNCTION_SET                    ; Set 4-bit mode
  jsr display_command_8bit_no_wait

  lda #(CMD_FUNCTION_SET | %01000)         ; Set 4-bit mode; 2-line display; 5x8 font
  jsr display_command

  lda #(CMD_DISPLAY_ON_OFF_CONTROL | %000) ; Display off; cursor off; blink off 
  jsr display_command

  lda #(CMD_CLEAR_DISPLAY)                 ; Clear display
  jsr display_command

  rts


wait_for_not_busy_8bit:
  pha
  lda DDRB
  pha
  and #(~DISPLAY_BITS_MASK & $ff)
  ora #(E | RW | RS) ; Set display control pins on port B to output; data pins to input
  sta DDRB
still_busy_8bit:
  lda #RW        ; Set RW flag for reading
  sta PORTB
  ora #E         ; Set E flag to trigger read
  sta PORTB
  lda PORTB
  and #BF        ; Check busy flag
  bne still_busy_8bit

  lda #RW        ; Clear E flag
  sta PORTB

  pla
  sta DDRB
  pla
  rts


display_command_8bit_no_wait:
  sta PORTB
  ora #E          ; Set E bit to send instruction
  sta PORTB
  and #(~E)       ; Clear E bit
  sta PORTB
  rts




test_routine:
  pha
  pla
  rts




wait_for_not_busy:
  pha
  sei
  lda DDRB
  and #(~DISPLAY_BITS_MASK & $ff)
  ora #(E | RW | RS) ; Set display control pins on port B to output; data pins to input
  sta DDRB
  cli
still_busy:
  lda #RW        ; Set RW flag for reading

  sei
  sta PORTB
  ora #E         ; Set E flag to trigger read
  sta PORTB
  lda PORTB
  and #BF        ; Check busy flag
  beq not_busy
  ; Read second 4 bits
  lda #RW
  sta PORTB
  ora #E
  sta PORTB
  cli

  jmp still_busy

not_busy:
  ; Read second 4 bits
  lda #RW
  sta PORTB
  ora #E
  sta PORTB
  lda #RW
  sta PORTB
  cli

  sei
  lda DDRB
  and #(~DISPLAY_BITS_MASK & $ff)
  ora #DISPLAY_BITS_MASK
  sta DDRB
  cli
  pla

  rts


display_command:
  jsr wait_for_not_busy
  pha
  and #%11110000

  sei
  sta PORTB
  ora #E          ; Set E bit to send instruction
  sta PORTB
  and #(~E)       ; Clear E bit
  sta PORTB

  pla
  asl
  asl
  asl
  asl

  sta PORTB
  ora #E          ; Set E bit to send instruction
  sta PORTB
  and #(~E & $ff) ; Clear E bit
  sta PORTB
  cli

  rts


display_character:
  jsr wait_for_not_busy
  pha
  and #%11110000

  ora #RS         ; Set RS bit
  sei
  sta PORTB
  ora #E          ; Set E bit to send instruction
  sta PORTB
  and #(~E & $ff) ; Clear E bit
  sta PORTB

  pla
  asl
  asl
  asl
  asl

  ora #RS         ; Set RS bit
  sta PORTB
  ora #E          ; Set E bit to send instruction
  sta PORTB
  and #(~E & $ff) ; Clear E bit
  sta PORTB
  cli

  rts


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


; On entry A = low source address
;          X = high byte source address
;          Y = character number
create_character:
  sta CREATE_CHARACTER_PARAM
  stx CREATE_CHARACTER_PARAM + 1

  tya
  asl
  asl
  asl
  ora #CMD_SET_CGRAM_ADDRESS
  jsr display_command

  ldy #0
create_loop:
  lda (CREATE_CHARACTER_PARAM),Y
  jsr display_character

  iny
  cpy #8
  bne create_loop

  rts


; On entry A = value to convert
; On exit  X = low result
;          A = high result
convert_to_hex:
  pha
  and #$0f
  cmp #10
  bcs convert_to_hex_character_low
  adc #'0'
  jmp convert_to_hex_done_low
convert_to_hex_character_low:
  clc
  adc #('A' - 10)
convert_to_hex_done_low:
  tax

  pla
  lsr
  lsr
  lsr
  lsr
  cmp #10
  bcs convert_to_hex_character_high
  adc #'0'
  rts
convert_to_hex_character_high:
  clc
  adc #('A' - 10)
  rts


character_pd:
  .byte %11000
  .byte %10101
  .byte %10101
  .byte %11001
  .byte %10011
  .byte %10101
  .byte %10101
  .byte %00011

character_angel:
  .byte %01110
  .byte %00000
  .byte %10101
  .byte %10101
  .byte %01110
  .byte %11111
  .byte %11111
  .byte %00000


  .org $ff00 ; Place code at start of page to ensure no page boundary crossings during timing loops

delay_10_thousandths:
  tax
outer_delay:       ; looking to have 100 cycles per iteration
  beq delay_done   ; 2 cycles
  
  ; 9 cycles outside of inner loop (excluding extra delay)
  ; need total of 100 - 9 = 91 extra cycles 
  ; 91 / 5 = 18.2 iterations
  ; 18 iterations = 17 * 5 + 4 = 89 cycles
  ; extra delay = 91 - 89 = 2 cycles
  nop              ; 2 cycles (extra delay)
  ldy #18          ; 2 cycles
inner_delay:       ; Per iteration: 5 cycles; 4 on last
  dey              ; 2 cycles
  bne inner_delay  ; 3 cycles

  dex              ; 2 cycles
  jmp outer_delay  ; 3 cycles
delay_done:
  rts

; Vectors
  .org $fffc
  .word reset
  .word interrupt
