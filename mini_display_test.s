  .include base_config_v1.inc

SD_DATA    = %00010000
SD_CLK     = %00100000
SD_DC      = %01000000

PORTA_SD_MASK = SD_DATA | SD_CLK | SD_DC | SD_CSB

SD_RST     = %10000000

PORTB_SD_MASK = SD_RST

D_S_I_P    = $00        ; 2 byte

  .org $2000
  jmp program_entry

  .include display_update_routines_4bit.inc
  .include display_string_immediate.inc
  .include delay_routines.inc

program_entry:
  jsr display_string_immediate
  .asciiz 'Mini display...'

  lda #(SD_DATA | SD_CLK | SD_DC | SD_CSB)
  trb PORTA
  lda #PORTA_SD_MASK
  tsb DDRA

  lda #SD_RST
  tsb PORTB
  lda #PORTB_SD_MASK
  tsb DDRB

  jsr sd_reset

  ; Set MUX Ratio
  lda #$a8
  jsr sd_send_command
  lda #$3f
  jsr sd_send_command

  ; Set display offset
  lda #$d3
  jsr sd_send_command
  lda #$00
  jsr sd_send_command

  ; Set display start line
  lda #$40
  jsr sd_send_command

  ; Set segment remap
  lda #$a1
  jsr sd_send_command

  ; Set COM Output Scan Direction
  lda #$c8
  jsr sd_send_command

  ; Set COM Pins Hardware
  lda #$da
  jsr sd_send_command
  lda #%00010010
  jsr sd_send_command

  ; Set Contrast Control
  lda #$81
  jsr sd_send_command
  lda #$7f
  jsr sd_send_command

  ; Disable Entire Display On
  lda #$a4
  jsr sd_send_command

  ; Set Normal Display
  lda #$a6
  jsr sd_send_command

  ; Set Osc Frequency
  lda #$d5
  jsr sd_send_command
  lda #$80
  jsr sd_send_command

  ; Enable charge pump regulator
  lda #$8d
  jsr sd_send_command
  lda #$14
  jsr sd_send_command

  ; Display on
  lda #$af
  jsr sd_send_command

  ldx #10
delay_loop:
  lda #100
  jsr delay_10_thousandths
  dex
  bne delay_loop

;  lda #$a5       ; All bits on
;  jsr sd_send_command

  lda #$20        ; Addressing mode
  jsr sd_send_command
  lda #%00
  jsr sd_send_command

display_repeat:
  lda #%00000001
display_outer_loop:

  tay

  ; Column start and end address
  lda #$21
  jsr sd_send_command
  lda #0
  jsr sd_send_command
  lda #127
  jsr sd_send_command

  ; Page start and end address
  lda #$22
  jsr sd_send_command
  lda #0
  jsr sd_send_command
  lda #7
  jsr sd_send_command

  tya

  ldx #0
display_loop:
  jsr sd_send_data
  jsr sd_send_data
  jsr sd_send_data
  jsr sd_send_data
  dex
  bne display_loop
  tay
  lda #10
  jsr delay_hundredths
  tya
  asl
  bcc display_outer_loop
  bra display_repeat

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  jsr display_string_immediate
  .asciiz 'Reset & on.'

  bra wait

flash_loop:
  lda #50
  jsr delay_hundredths

  ; Inverse display
  ;lda #$a7
  ;jsr sd_send_command

  lda #$a5
  jsr sd_send_command

  lda #50
  jsr delay_hundredths

  ; Non-inverse display
  ;lda #$a6
  ;jsr sd_send_command

  lda #$a4
  jsr sd_send_command

  bra flash_loop



wait:
  bra wait

; Write command: SD_CS   = 0 ; L
;                SD_DC   = 0 ; L
;                SD_DATA = X
;                SD_CLK  = 0 to 1; L to H


sd_send_command:
  pha
  phx
  phy
  tay
  lda #SD_DC
  trb PORTA
  bra sd_send

sd_send_data:
  pha
  phx
  phy
  tay
  lda #SD_DC
  tsb PORTA
  bra sd_send

sd_send:
  ldx #8
sd_send_loop:
  tya
  asl
  tay
  lda #SD_DATA
  bcs sd_high_bit
; low bit
  trb PORTA
  bra sd_bit_set
sd_high_bit:
  tsb PORTA
sd_bit_set:
  lda #SD_CLK
  tsb PORTA
  trb PORTA
  dex
  bne sd_send_loop

  ply
  plx
  pla
  rts


sd_reset:
  lda #SD_RST
  tsb PORTB

  lda #10 ; 1 millisecond
  jsr delay_10_thousandths

  lda #SD_RST
  trb PORTB

  lda #100 ; 10 milliseconds
  jsr delay_10_thousandths

  lda #SD_RST
  tsb PORTB

  rts
