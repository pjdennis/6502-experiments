  .include base_config_v1.inc

SD_DATA = %00010000
SD_CLK  = %00100000
SD_DC   = %01000000
SD_CSB  = %10000000

PORTA_SD_MASK = SD_DATA | SD_CLK | SD_DC | SD_CSB

SD_RST  = %10000000

PORTB_SD_MASK = SD_RST

D_S_I_P  = $00        ; 2 bytes
SCREEN_P = $02        ; 2 bytes
X0IN     = $04
Y0IN     = $05
X1IN     = $06
Y1IN     = $07
X0       = $08
Y0       = $09
X1       = X1IN
Y1       = Y1IN
DX       = $0a
DYL      = $0b
DYH      = $0c
SX       = $0d
SY       = $0e
ERRL     = $0f
ERRH     = $10
E2L      = $11
E2H      = $12

SCREEN_WIDTH = 128
SCREEN_PAGES = 8
SCREEN_BYTES = SCREEN_WIDTH * SCREEN_PAGES

SCREEN_BUFFER           = $3f00 - SCREEN_BYTES
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

  lda #(SD_DATA | SD_CLK | SD_DC | SD_CSB)
  trb PORTA
  lda #PORTA_SD_MASK
  tsb DDRA

  lda #SD_RST
  tsb PORTB
  lda #PORTB_SD_MASK
  tsb DDRB

  jsr sd_initialize

  jsr clear_screen_buffer

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor

  lda #0
  sta X0IN
  lda #0
  sta Y0IN
  lda #127
  sta X1IN

  lda #0
  sta Y1IN
  jsr draw_line

  lda #8
  sta Y1IN
  jsr draw_line

  lda #16
  sta Y1IN
  jsr draw_line

  lda #24
  sta Y1IN
  jsr draw_line

  lda #32
  sta Y1IN
  jsr draw_line

  lda #40
  sta Y1IN
  jsr draw_line

  lda #48
  sta Y1IN
  jsr draw_line

  lda #56
  sta Y1IN
  jsr draw_line

  lda #63
  sta Y1IN
  jsr draw_line

  lda #120
  sta X1IN
  jsr draw_line

  lda #112
  sta X1IN
  jsr draw_line

  lda #104
  sta X1IN
  jsr draw_line

  lda #96
  sta X1IN
  jsr draw_line

  lda #88
  sta X1IN
  jsr draw_line

  lda #80
  sta X1IN
  jsr draw_line

  lda #72
  sta X1IN
  jsr draw_line

  lda #64
  sta X1IN
  jsr draw_line

  lda #56
  sta X1IN
  jsr draw_line

  lda #48
  sta X1IN
  jsr draw_line

  lda #40
  sta X1IN
  jsr draw_line

  lda #32
  sta X1IN
  jsr draw_line

  lda #24
  sta X1IN
  jsr draw_line

  lda #16
  sta X1IN
  jsr draw_line

  lda #8
  sta X1IN
  jsr draw_line

  lda #0
  sta X1IN
  jsr draw_line

  jsr send_screen_buffer

  jsr display_string_immediate
  .asciiz "Done."

wait:
  bra wait


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


sd_initialize:
  pha

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

  ; Set addressing mode
  lda #$20
  jsr sd_send_command
  lda #%00
  jsr sd_send_command

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


set_quad_pixel:
  pha
  phx
  phy

  tya
  asl
  tay

  txa
  asl
  tax

  jsr set_pixel
  inx
  jsr set_pixel
  iny
  jsr set_pixel
  dex
  jsr set_pixel

  ply
  plx
  pla
  rts


; On Entry X0IN, Y0IN contain one end of the line to be drawn
;          X1, Y1 contain the other end of the line to be drawn
draw_line:
  lda X0IN
  sta X0
  lda Y0IN
  sta Y0

  ; DX = abs(X1 - X0)
  sec
  lda X1
  sbc X0
  bcs draw_line_dx_ready
  eor #$ff
  adc #1
draw_line_dx_ready:
  sta DX

  ; SX = X0 < X1 ? 1 : -1
  lda X0
  cmp X1
  bmi draw_line_sx_one
  lda #-1
  bra draw_line_sx_ready
draw_line_sx_one:
  lda #1
draw_line_sx_ready:
  sta SX

  ; DY = -abs(Y1 - Y0)
  sec
  lda Y1
  sbc Y0
  bcc draw_line_dy_ready
  eor #$ff
  adc #0 ; since carry is set this will add 1
draw_line_dy_ready:
  sta DYL
  asl
  lda #0
  adc #$ff
  eor #$ff
  sta DYH

  ; SY = Y0 < Y1 ? 1 : -1
  lda Y0
  cmp Y1
  bmi draw_line_sy_one
  lda #-1
  bra draw_line_sy_ready
draw_line_sy_one:
  lda #1
draw_line_sy_ready:
  sta SY

  ; ERR = DX + DY
  clc
  lda DX
  adc DYL
  sta ERRL
  lda #0    ; DXH
  adc DYH
  sta ERRH

  ; while (true)
draw_line_loop:

  ; plot(X0, Y0)
  ldx X0
  ldy Y0
  jsr set_pixel

  ; if (X0 == X1 && Y0 == Y1) break
  lda X0
  cmp X1
  bne draw_line_not_done
  lda Y0
  cmp Y1
  beq draw_line_done
draw_line_not_done:

  ; E2 = 2 * ERR
  lda ERRL
  asl
  sta E2L
  lda ERRH
  rol
  sta E2H

  ; if (E2 >= DY)
  ;   A >= NUM - BPL will branch
  ;   A < NUM  - BMI will branch
  ;   A-NUM
  ;   NUM1-NUM2
  ;   A === NUM1; NUM === NUM2
  ;   NUM1 >= NUM2 - BPL will branch
  ;   NUM1 <  NUM2 - BMI will branch
  ;   if E2 < DY - skip
  ;   E2 === NUM1; DY === NUM2
  lda E2L  ; NUM1L ; NUM1 - NUM2 ; E2 - DY
  cmp DYL  ; NUM2L
  lda E2H  ; NUM1H
  sbc DYH  ; NUM2H
  bvc draw_line_e2_dy_compare_ready
  eor #$80
draw_line_e2_dy_compare_ready:
  bmi draw_line_dy_sx_incorporated

  ; ERR += DY
  clc
  lda ERRL
  adc DYL
  sta ERRL
  lda ERRH
  adc DYH
  sta ERRH

  ; X0 += SX
  clc
  lda X0
  adc SX
  sta X0

draw_line_dy_sx_incorporated:

  ; if (E2 <= DX)
  ;   A >= NUM - BPL will branch
  ;   A < NUM  - BMI will branch
  ;   A-NUM
  ;   NUM1-NUM2
  ;   A === NUM1; NUM === NUM2
  ;   NUM1 >= NUM2 - BPL will branch
  ;   NUM1 <  NUM2 - BMI will branch
  ;   if DX < E2 - skip
  ;   DX === NUM1; E2 === NUM2 
  lda DX   ; NUM1L ; NUM1 - NUM2 ; DX - E2
  cmp E2L  ; NUM2L
  lda #0   ; NUM1H
  sbc E2H  ; NUM2H
  bvc draw_line_e2_dx_compare_ready
  eor #$80
draw_line_e2_dx_compare_ready:
  bmi draw_line_loop

  ; ERR += DX
  clc
  lda ERRL
  adc DX
  sta ERRL
  lda ERRH
  adc #0
  sta ERRH
  
  ; Y0 += SY
  clc
  lda Y0
  adc SY
  sta Y0

  bra draw_line_loop  

draw_line_done:
  rts

forever:
  bra forever
