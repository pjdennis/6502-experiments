  .include base_config_wendy2c.inc

ILI9341_RDMODE     = $0a
ILI9341_RDMADCTL   = $0b
ILI9341_RDSELFDIAG = $0f
ILI9341_RDPIXFMT   = $0c

DISPLAY_STRING_PARAM  = $00 ; 2 bytes

  .org $4000
  jmp program_entry

  ; Place code for delay_routines at start of page to ensure no page boundary crossings
  ; during timing loops
  .include delay_routines.inc

  .include display_routines_4bit.inc
  .include display_hex.inc
  .include display_string.inc

program_entry:
  jsr clear_display

  lda #<message
  ldx #>message
  jsr display_string

  jsr gd_select

  jsr gd_reset

  lda #ILI9341_RDMADCTL
  jsr gd_send_command

  jsr gd_receive_data

  jsr gd_unselect

  jsr display_hex

  jsr gd_select
  lda #ILI9341_RDMODE 
  jsr gd_send_command
  jsr gd_receive_data
  jsr gd_unselect
  jsr display_hex

  jsr gd_select
  lda #ILI9341_RDSELFDIAG 
  jsr gd_send_command
  jsr gd_receive_data
  jsr gd_unselect
  jsr display_hex

  jsr gd_select
  lda #ILI9341_RDPIXFMT
  jsr gd_send_command
  jsr gd_receive_data
  jsr gd_unselect
  jsr display_hex

  stp


;  lda #DISPLAY_SECOND_LINE
;  jsr move_cursor

message: asciiz "Config:"

gd_select:
  pha
  lda #GD_CLK | GD_DC
  trb GD_PORT
  lda #GD_MOSI
  tsb GD_PORT
  lda #GD_CLK | GD_DC | GD_MOSI
  tsb GD_PORT + DDR_OFFSET
  lda #GD_MISO
  trb GD_PORT + DDR_OFFSET
  lda #GD_CSB
  trb GD_PORT
  pla
  rts

gd_unselect:
  pha
  lda #GD_CSB
  tsb GD_PORT
  lda #DISPLAY_BITS_MASK
  trb DISPLAY_DATA_PORT
  tsb DISPLAY_DATA_PORT + DDR_OFFSET
  pla
  rts

gd_reset:
  pha
  lda #1
  jsr delay_hundredths
  lda #GD_RSTB
  trb GD_PORT
  lda #10
  jsr delay_hundredths
  lda #GD_RSTB
  tsb GD_PORT
  lda #20
  jsr delay_hundredths
  pla
  rts 

gd_send_command:
  pha
  phx
  phy
  tay
  lda #GD_DC
  trb GD_PORT
  bra gd_send

gd_send_data:
  pha
  phx
  phy
  tay
  lda #GD_DC
  tsb GD_PORT
  bra gd_send

gd_send:
  ldx #8
.loop:
  tya
  asl
  tay
  lda #GD_MOSI
  bcs .high_bit
; low bit
  trb GD_PORT
  bra .bit_set
.high_bit:
  tsb GD_PORT
.bit_set:
  lda #GD_CLK
  tsb GD_PORT
  trb GD_PORT
  dex
  bne .loop

  ply
  plx
  pla
  rts


; On exit A = the received byte
gd_receive_data:
  phx
  phy
  lda #GD_DC
  tsb GD_PORT
  ldy #0
  ldx #8
.loop
  lda #GD_CLK
  tsb GD_PORT
  lda #GD_MISO
  bit GD_PORT
  bne .high_bit
; low bit
  tya
  asl
  bra .bit_set
.high_bit:
  tya
  asl
  inc
.bit_set
  tay
  lda #GD_CLK
  trb GD_PORT
  dex
  bne .loop
  tya
  ply
  plx
  rts
