CLOCK_FREQ_KHZ = 2000

PORTB  = $F000
PORTA  = $F001
DDRB   = $F002
DDRA   = $F003

DISPLAY_DATA_PORT = PORTA
DISPLAY_DATA_DDR  = DDRA
DISPLAY_DATA_MASK = %11110000
RW                = %00001000
RS                = %00000100
BF                = %10000000
DISPLAY_BITS_MASK = (DISPLAY_DATA_MASK | RW | RS)

DISPLAY_ENABLE_PORT = PORTB
DISPLAY_ENABLE_DDR  = DDRB
E                   = %00100000
DISPLAY_ENABLE_MASK = E

BANK_PORT  = PORTB
BANK_DDR   = DDRB
BANK_MASK  = %00011111
BANK_START = %00000100

FIXED_RAM        = $4000
FIXED_RAM_OFFSET = program_start - FIXED_RAM
PROGRAM_LENGTH   = program_end - program_start

DISPLAY_STRING_PARAM = $00 ; 2 bytes
CP_M_DEST_P          = $02 ; 2 bytes
CP_M_SRC_P           = $04 ; 2 bytes
CP_M_LEN             = $06 ; 2 bytes


  .org $8000
program_start:

  .include display_parameters.inc
  .include delay_routines.inc
  .include display_init_helpers.inc
  .include display_update_helpers.inc
  .include display_string.inc
  .include copy_memory.inc                ; We're relying on this code being relocatable


switch_to_ram:
  ; copy PROGRAM_LENGTH bytes from program_start to FIXED_RAM
  lda #<FIXED_RAM
  sta CP_M_DEST_P
  lda #>FIXED_RAM
  sta CP_M_DEST_P + 1
  lda #<program_start
  sta CP_M_SRC_P
  lda #>program_start
  sta CP_M_SRC_P + 1
  lda #<PROGRAM_LENGTH
  sta CP_M_LEN
  lda #>PROGRAM_LENGTH
  sta CP_M_LEN + 1
  jsr copy_memory

  ; jmp to switch_to_ram_part_2 within FIXED_RAM (switch_to_ram_part_2 - FIXED_RAM_OFFSET)
  jmp switch_to_ram_part_2 - FIXED_RAM_OFFSET


switch_to_ram_part_2:
  ; switch out ROM for RAM
  lda #BANK_MASK
  trb BANK_PORT
  tsb BANK_DDR

  lda #BANK_START
  tsb BANK_PORT

  ldx #$ff                                 ; Initialize stack
  txs

  ; copy PROGRAM_LENGTH bytes from FIXED_RAM to program_start
  lda #<program_start
  sta CP_M_DEST_P
  lda #>program_start
  sta CP_M_DEST_P + 1
  lda #<FIXED_RAM
  sta CP_M_SRC_P
  lda #>FIXED_RAM
  sta CP_M_SRC_P + 1
  lda #<PROGRAM_LENGTH
  sta CP_M_LEN
  lda #>PROGRAM_LENGTH
  sta CP_M_LEN + 1
  jsr copy_memory - FIXED_RAM_OFFSET

  ; return to the calling code
  jmp continue_in_ram


; Set port directions
initialize_ports_for_display:
  lda #DISPLAY_BITS_MASK
  tsb DISPLAY_DATA_DDR
  trb DISPLAY_DATA_PORT

  lda #DISPLAY_ENABLE_MASK
  tsb DISPLAY_ENABLE_DDR
  trb DISPLAY_ENABLE_PORT

  rts


; Reset sequence per datasheet
reset_display:
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

  jsr clear_display

  rts


wait_for_not_busy_8bit:
  pha
  phx

  lda #DISPLAY_DATA_MASK  ; Set display data pins to input
  trb DISPLAY_DATA_DDR
  lda #RW                 ; Set RW (read) flag for reading
  tsb DISPLAY_DATA_PORT
still_busy_8bit:
  lda #E
  tsb DISPLAY_ENABLE_PORT ; Set E flag to trigger read
  ldx DISPLAY_DATA_PORT
  trb DISPLAY_ENABLE_PORT ; Clear E flag

  txa
  and #BF                 ; Check busy flag
  bne still_busy_8bit
  ; Not busy
  lda #DISPLAY_BITS_MASK
  trb DISPLAY_DATA_PORT   ; Clear the RW (read) flag and data bits ready for next send

  lda #DISPLAY_DATA_MASK
  tsb DISPLAY_DATA_DDR    ; Set display data pins to output

  plx
  pla
  rts


; On input A = command to send
display_command_8bit_no_wait:
  pha                     ; might not need this
  lda #DISPLAY_DATA_MASK
  trb DISPLAY_DATA_PORT
  pla

  ; Here's where we would shift the high nybble to match the data mask position
  and #DISPLAY_DATA_MASK
  tsb DISPLAY_DATA_PORT

  lda #E
  tsb DISPLAY_ENABLE_PORT ; Set E bit to send instruction
  trb DISPLAY_ENABLE_PORT ; Clear E bit

  lda #DISPLAY_DATA_MASK
  trb DISPLAY_ENABLE_PORT ; Clear data ready for next send       

  rts


wait_for_not_busy:
  pha
  phx

still_busy:
  lda #DISPLAY_DATA_MASK  ; - Set display data pins on port B to input
  trb DISPLAY_DATA_DDR

  lda #RW
  tsb DISPLAY_DATA_PORT   ; - Set RW (read) flag for reading

  lda #E
  tsb DISPLAY_ENABLE_PORT ; - Set E flag to trigger read of first 4 bits
  ldx DISPLAY_DATA_PORT   ; - Read data value from port
  trb DISPLAY_ENABLE_PORT ; - Clear E flag

  tsb DISPLAY_ENABLE_PORT ; - Set E flag to trigger read of second 4 bits
  trb DISPLAY_ENABLE_PORT ; - Clear E flag

  lda #DISPLAY_BITS_MASK
  trb DISPLAY_DATA_PORT   ; - Clear the RW flag and set data bits back to 0 ready for next send

  lda #DISPLAY_DATA_MASK
  tsb DISPLAY_DATA_DDR    ; - Set display data pins on port B back to output

  txa
  and #BF                 ; Check busy flag
  bne still_busy
  ; Not busy

  plx
  pla
  rts


; On Entry A = Command to send
; On Exit  X, Y preserved
;          A not preserved
display_command:
  phx
  ldx #0                  ; RS flag not set for command
  bra send_to_display

; On Entry A = Character to send
; On Exit  X, Y preserved
;          A not preserved
display_character:
  phx
  ldx #RS                 ; RS flag set for accessing display memory  
  ; fall through

send_to_display:
  phy
  jsr wait_for_not_busy
  
  pha
  asl                     ; Shift lower byte to display data location
  asl
  asl
  asl
  and #DISPLAY_DATA_MASK
  tay                     ; Second 4 bits to send are in Y
  pla

  ; Here is where we would shift upper byte to display data location

  and #DISPLAY_DATA_MASK  ; First 4 bits to send are in A

  tsb DISPLAY_DATA_PORT   ; - Output the command first 4 bits
  txa                     ; - Flag for type of command to send is in X
  tsb DISPLAY_DATA_PORT   ; - Set flag (RS or not) to indicate command vs character
  lda #E                  ;
  tsb DISPLAY_ENABLE_PORT ; - Set E bit to send instruction
  trb DISPLAY_ENABLE_PORT ; - Clear E bit
  lda #DISPLAY_DATA_MASK  ;
  trb DISPLAY_DATA_PORT   ; - Clear data lines ready for next send
                          ;
  tya                     ;
  tsb DISPLAY_DATA_PORT   ; - Output the command second 4 bits
  lda #E                  ;
  tsb DISPLAY_ENABLE_PORT ; - Set E bit to send instruction
  trb DISPLAY_ENABLE_PORT ; - Clear E bit
  lda #DISPLAY_BITS_MASK  ;
  trb DISPLAY_DATA_PORT   ; - Clear data lines and command flags ready for next send

  ply
  plx
  rts



message: .asciiz "Hi! I'm Wendy 2"


reset:

  ldx #$ff                                 ; Initialize stack
  txs

  lda #0                                   ; Initialize status flags
  pha
  plp

  jmp switch_to_ram

continue_in_ram:


  lda #'I'
  sta message + 1

  jsr initialize_ports_for_display         ; Prepare the display
  jsr reset_and_enable_display_no_cursor


  lda #%01000000                           ; Prepare to flash LED
  tsb DDRB

loop:
  lda #%01000000
  tsb PORTB

  lda #<message                            ; Display a message
  ldx #>message
  jsr display_string

  jsr delay

  lda #%01000000
  trb PORTB                                ; Light is on when low

  jsr clear_display

  jsr delay

  bra loop

delay:
  ldx #0
loop2:

  ldy #0
loop3:
  nop
  nop
  nop
  nop
  dey
  bne loop3

  dex
  bne loop2

  rts


program_end:


  .org $fffc
  .word reset
  .word $0000
 

