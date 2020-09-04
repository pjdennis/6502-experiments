  .include base_config_v1.inc

SD_DATA    = %00010000
SD_CLK     = %00100000
SD_DC      = %01000000
SD_CSB     = %10000000

PORTA_SD_MASK = SD_DATA | SD_CLK | SD_DC | SD_CSB

SD_RST     = %10000000

PORTB_SD_MASK = SD_RST

D_S_I_P    = $00        ; 2 bytes
SCREEN_P   = $02        ; 2 bytes

X1_STACK   = $200
Y1_STACK   = $300
X2_STACK   = $400
Y2_STACK   = $500

SCREEN_WIDTH = 128
SCREEN_PAGES = 8
SCREEN_BYTES = SCREEN_WIDTH * SCREEN_PAGES

SCREEN_BUFFER = $3f00 - SCREEN_BYTES
SCREEN_BUFFER_LAST_PAGE = SCREEN_BUFFER + SCREEN_WIDTH * (SCREEN_PAGES - 1)

  .org $2000
  jmp program_entry

  .include display_update_routines.inc
  .include display_string_immediate.inc
  .include display_hex.inc
  .include delay_routines.inc

program_entry:
  jsr display_string_immediate
  .asciiz 'Mini display...'

  jsr clear_screen_buffer

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


;  jsr draw_box_around_screen


;  ldx #0
;  ldy #0
;  jsr set_pixel

;  ldx #10
;  ldy #0
;  jsr set_pixel

;  ldx #0
;  ldy #4
;  jsr set_pixel

;  ldx #0
;  ldy #8
;  jsr set_pixel

;  ldx #127
;  ldy #63
;  jsr set_pixel

;  ldx #20
;  ldy #10
;line_loop:
;  jsr set_pixel
;  inx
;  jsr set_pixel
;  inx
;  iny
;  cpy #40
;  bne line_loop

  jsr send_screen_buffer

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor

;  ldx #0
;  ldy #2
;  jsr set_pixel

;  ldx #2
;  ldy #2
;  jsr set_pixel


  lda #0
  sta X1_STACK
  lda #0
  sta Y1_STACK

  lda #127
  sta X2_STACK
  lda #63
  sta Y2_STACK

  ldy #0
  jsr draw_line


  jsr send_screen_buffer

  jsr display_string_immediate
  .asciiz "Done."

  jmp wait


screen_loop:
  jsr draw_box_around_screen
  jsr send_screen_buffer

  lda #50
  jsr delay_hundredths

  jsr clear_screen_buffer
  jsr send_screen_buffer

  lda #50
  jsr delay_hundredths

  bra screen_loop

  jmp wait

display_repeat:
  lda #%00000001
display_outer_loop:

  tay

  ; Column start and end address
  lda #$21
  jsr sd_send_command
  lda #0
  jsr sd_send_command
  lda #63
  jsr sd_send_command

  ; Page start and end address
  lda #$22
  jsr sd_send_command
  lda #0
  jsr sd_send_command
  lda #3
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


send_screen_buffer:
  pha
  phx
  phy

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

  lda #SD_DC ; Data
  tsb PORTA

  lda #<SCREEN_BUFFER
  sta SCREEN_P
  lda #>SCREEN_BUFFER
  sta SCREEN_P + 1

send_screen_buffer_loop:
  lda (SCREEN_P)
  ldx #8
send_screen_buffer_byte_loop:
  asl
  tay
  lda #SD_DATA
  bcs send_screen_buffer_high_bit
  trb PORTA
  lda #SD_CLK
  tsb PORTA
  trb PORTA
  tya
  dex
  bne send_screen_buffer_byte_loop
  bra send_screen_buffer_byte_done
send_screen_buffer_high_bit:
  tsb PORTA
  lda #SD_CLK
  tsb PORTA
  trb PORTA
  tya
  dex
  bne send_screen_buffer_byte_loop
send_screen_buffer_byte_done:
  inc SCREEN_P
  bne send_screen_buffer_loop
  inc SCREEN_P + 1
  lda #>(SCREEN_BUFFER + SCREEN_BYTES)
  cmp SCREEN_P + 1
  bne send_screen_buffer_loop

  ply
  plx
  pla
  rts


clear_screen_buffer:
  phx
  ldx #0
clear_screen_buffer_loop:
  stz SCREEN_BUFFER+$000,X
  stz SCREEN_BUFFER+$100,X
  stz SCREEN_BUFFER+$200,X
  stz SCREEN_BUFFER+$300,X
  inx
  bne clear_screen_buffer_loop
  plx
  rts

draw_box_around_screen:
  pha
  phx
  phy

  lda #<SCREEN_BUFFER
  sta SCREEN_P
  lda #>SCREEN_BUFFER
  sta SCREEN_P + 1

  lda #%11111111
  ldx #8
vertical_loop:
  sta (SCREEN_P)
  ldy #SCREEN_WIDTH - 1
  sta (SCREEN_P),Y
  iny
  sta (SCREEN_P),Y
  ldy #SCREEN_WIDTH * 2 - 1
  sta (SCREEN_P),Y
  inc SCREEN_P + 1
  dex
  bne vertical_loop

  ldx #SCREEN_WIDTH - 2
horizontal_loop:
  lda #%00000001
  sta SCREEN_BUFFER,X
  lda #%10000000
  sta SCREEN_BUFFER_LAST_PAGE,X
  dex
  bne horizontal_loop

  ply
  plx
  pla
  rts


PIXEL_MASKS:
  .byte %00000001
  .byte %00000010
  .byte %00000100
  .byte %00001000
  .byte %00010000
  .byte %00100000
  .byte %01000000
  .byte %10000000

BANK_START_LOCATIONS_L:
  .byte <(SCREEN_BUFFER + SCREEN_WIDTH * 0)
  .byte <(SCREEN_BUFFER + SCREEN_WIDTH * 1)
  .byte <(SCREEN_BUFFER + SCREEN_WIDTH * 2)
  .byte <(SCREEN_BUFFER + SCREEN_WIDTH * 3)
  .byte <(SCREEN_BUFFER + SCREEN_WIDTH * 4)
  .byte <(SCREEN_BUFFER + SCREEN_WIDTH * 5)
  .byte <(SCREEN_BUFFER + SCREEN_WIDTH * 6)
  .byte <(SCREEN_BUFFER + SCREEN_WIDTH * 7)

BANK_START_LOCATIONS_H
  .byte >(SCREEN_BUFFER + SCREEN_WIDTH * 0)
  .byte >(SCREEN_BUFFER + SCREEN_WIDTH * 1)
  .byte >(SCREEN_BUFFER + SCREEN_WIDTH * 2)
  .byte >(SCREEN_BUFFER + SCREEN_WIDTH * 3)
  .byte >(SCREEN_BUFFER + SCREEN_WIDTH * 4)
  .byte >(SCREEN_BUFFER + SCREEN_WIDTH * 5)
  .byte >(SCREEN_BUFFER + SCREEN_WIDTH * 6)
  .byte >(SCREEN_BUFFER + SCREEN_WIDTH * 7)

; On Entry X = X coordinate relative to left of screen
;          Y - Y coordinate relative to top of screen
set_pixel:
  pha
  phx
  phy

  ; Y / 8 tells us which bank
  tya
  lsr ; Divide by 8
  lsr
  lsr

  ; Multiply by 2 due to 

  phx ; Push the X coordinate
  tax

  lda BANK_START_LOCATIONS_L,X
  sta SCREEN_P

  lda BANK_START_LOCATIONS_H,X
  sta SCREEN_P + 1

  ; Y mod 8 tells us which mask
  tya
  and #%00000111
  tax
  lda PIXEL_MASKS,X
  ply ; Pull X coordinate into Y register
  ora (SCREEN_P),Y
  sta (SCREEN_P),Y

  ply
  plx
  pla
  rts


; On entry, Y indexes to the current point pair
draw_line:
  lda X1_STACK,Y
  cmp X2_STACK,Y
  beq draw_line_x_match
  inc
  cmp X2_STACK,Y
  beq draw_line_x_match
  dec
  dec
  cmp X2_STACK,Y
  bne draw_line_continue
draw_line_x_match:
  lda Y1_STACK,Y
  cmp Y2_STACK,Y
  beq draw_line_y_match
  inc
  cmp Y2_STACK,Y
  beq draw_line_y_match
  dec
  dec
  cmp Y2_STACK,Y
  bne draw_line_continue
draw_line_y_match:
; Draw the points
  phy
  lda X1_STACK,Y
  tax
  lda Y1_STACK,Y
  tay
  jsr set_pixel

  lda X2_STACK,Y
  tax
  lda Y2_STACK,Y
  tay
  jsr set_pixel

  jsr send_screen_buffer
  ply
  rts
draw_line_continue:
  clc
  lda X1_STACK,Y
  adc X2_STACK,Y
  lsr
  sta X1_STACK+1,Y

  clc
  lda Y1_STACK,Y
  adc Y2_STACK,Y
  lsr
  sta Y1_STACK+1,Y

  lda X1_STACK,Y
  sta X2_STACK+1,Y
  lda Y1_STACK,Y
  sta Y2_STACK+1,Y

  iny
  jsr draw_line
  dey

  lda X2_STACK,Y
  sta X2_STACK+1,Y
  lda Y2_STACK,Y
  sta Y2_STACK+1,Y

  iny
  jsr draw_line
  dey

  rts

