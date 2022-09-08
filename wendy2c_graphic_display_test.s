  .include base_config_wendy2c.inc

ILI9341_TFTWIDTH  = 240 ; ILI9341 max TFT width
ILI9341_TFTHEIGHT = 320 ; ILI9341 max TFT height

ILI9341_NOP     = $00 ; No-op register
ILI9341_SWRESET = $01 ; Software reset register
ILI9341_RDDID   = $04 ; Read display identification information
ILI9341_RDDST   = $09 ; Read Display Status

ILI9341_SLPIN  = $10 ; Enter Sleep Mode
ILI9341_SLPOUT = $11 ; Sleep Out
ILI9341_PTLON  = $12 ; Partial Mode ON
ILI9341_NORON  = $13 ; Normal Display Mode ON

ILI9341_RDMODE     = $0a ; Read Display Power Mode
ILI9341_RDMADCTL   = $0b ; Read Display MADCTL
ILI9341_RDPIXFMT   = $0c ; Read Display Pixel Format
ILI9341_RDIMGFMT   = $0d ; Read Display Image Format
ILI9341_RDSELFDIAG = $0f ; Read Display Self-Diagnostic Result

ILI9341_INVOFF   = $20 ; Display Inversion OFF
ILI9341_INVON    = $21 ; Display Inversion ON
ILI9341_GAMMASET = $26 ; Gamma Set
ILI9341_DISPOFF  = $28 ; Display OFF
ILI9341_DISPON   = $29 ; Display ON

ILI9341_CASET = $2a ; Column Address Set
ILI9341_PASET = $2b ; Page Address Set
ILI9341_RAMWR = $2c ; Memory Write
ILI9341_RAMRD = $2e ; Memory Read

ILI9341_PTLAR    = $30 ; Partial Area
ILI9341_VSCRDEF  = $33 ; Vertical Scrolling Definition
ILI9341_MADCTL   = $36 ; Memory Access Control
ILI9341_VSCRSADD = $37 ; Vertical Scrolling Start Address
ILI9341_PIXFMT   = $3a ; COLMOD: Pixel Format Set

ILI9341_FRMCTR1 = $b1 ; Frame Rate Control (In Normal Mode/Full Colors)
ILI9341_FRMCTR2 = $b2 ; Frame Rate Control (In Idle Mode/8 colors)
ILI9341_FRMCTR3 = $b3 ; Frame Rate control (In Partial Mode/Full Colors)
ILI9341_INVCTR  = $b4 ; Display Inversion Control
ILI9341_DFUNCTR = $b6 ; Display Function Control

ILI9341_PWCTR1 = $c0 ; Power Control 1
ILI9341_PWCTR2 = $c1 ; Power Control 2
ILI9341_PWCTR3 = $c2 ; Power Control 3
ILI9341_PWCTR4 = $c3 ; Power Control 4
ILI9341_PWCTR5 = $c4 ; Power Control 5
ILI9341_VMCTR1 = $c5 ; VCOM Control 1
ILI9341_VMCTR2 = $c7 ; VCOM Control 2

ILI9341_RDID1 = $da ; Read ID 1
ILI9341_RDID2 = $db ; Read ID 2
ILI9341_RDID3 = $dc ; Read ID 3
ILI9341_RDID4 = $dd ; Read ID 4

ILI9341_GMCTRP1 = $e0 ; Positive Gamma Correction
ILI9341_GMCTRN1 = $e1 ; Negative Gamma Correction
;ILI9341_PWCTR6 = $fc

; Color definitions
ILI9341_BLACK       = $0000 ;   0,   0,   0
ILI9341_NAVY        = $000f ;   0,   0, 123
ILI9341_DARKGREEN   = $03e0 ;   0, 125,   0
ILI9341_DARKCYAN    = $03ef ;   0, 125, 123
ILI9341_MAROON      = $7800 ; 123,   0,   0
ILI9341_PURPLE      = $780f ; 123,   0, 123
ILI9341_OLIVE       = $7be0 ; 123, 125,   0
ILI9341_LIGHTGREY   = $c618 ; 198, 195, 198
ILI9341_DARKGREY    = $7bef ; 123, 125, 123
ILI9341_BLUE        = $001f ;   0,   0, 255
ILI9341_GREEN       = $07e0 ;   0, 255,   0
ILI9341_CYAN        = $07ff ;   0, 255, 255
ILI9341_RED         = $f800 ; 255,   0,   0
ILI9341_MAGENTA     = $f81f ; 255,   0, 255
ILI9341_YELLOW      = $ffe0 ; 255, 255,   0
ILI9341_WHITE       = $ffff ; 255, 255, 255
ILI9341_ORANGE      = $fd20 ; 255, 165,   0
ILI9341_GREENYELLOW = $afe5 ; 173, 255,  41
ILI9341_PINK        = $fc18 ; 255, 130, 198


DISPLAY_STRING_PARAM  = $00 ; 2 bytes
CMD_PTR               = $02 ; 2 bytes

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
  jsr gd_initialize
  jsr gd_unselect

  jsr gd_select
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

  jsr gd_select
  jsr show_content
  jsr gd_unselect

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
  lda #1 ; could be 1 ms
  jsr delay_hundredths
  lda #GD_RSTB
  trb GD_PORT
  lda #1 ; 10 ms
  jsr delay_hundredths
  lda #GD_RSTB
  tsb GD_PORT
  lda #12 ; 120 ms
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


show_content:
  lda #ILI9341_CASET
  jsr gd_send_command
  lda #0
  jsr gd_send_data
  lda #0
  jsr gd_send_data
  lda #0
  jsr gd_send_data
  lda #10
  jsr gd_send_data

  lda #ILI9341_PASET
  jsr gd_send_command
  lda #0
  jsr gd_send_data
  lda #0
  jsr gd_send_data
  lda #0
  jsr gd_send_data
  lda #10
  jsr gd_send_data

  lda #ILI9341_RAMWR
  jsr gd_send_command

  ldx #100
.loop:
  lda #>ILI9341_RED
  jsr gd_send_data
  lda #<ILI9341_RED
  jsr gd_send_data
  dex
  bne .loop

  rts


gd_initialize:
  pha
  phx
  phy
  lda #<INIT_COMMANDS
  sta CMD_PTR
  lda #>INIT_COMMANDS
  sta CMD_PTR + 1
.loop:
  jsr .next_byte
  cmp #0
  beq .done
  jsr gd_send_command
  jsr .next_byte
  tay
  and #$7f
  tax
  beq .param_done
.param_loop:
  jsr .next_byte
  jsr gd_send_data
  dex
  bne .param_loop
.param_done:
  tya
  and #$80
  beq .loop
  jsr .delay
  bra .loop
.done:
  ply
  plx
  pla
  rts
.next_byte:
  lda (CMD_PTR)
  inc CMD_PTR
  bne .next_byte_over
  inc CMD_PTR + 1
.next_byte_over:
  rts
.delay:
  lda #15
  jsr delay_hundredths
  rts


test_command:
  pha
  lda #'C'
  jsr display_character
  pla
  jsr display_hex
  rts

test_parameter:
  jsr display_hex
  rts

test_delay:
  lda #'D'
  jsr display_character
  rts

INIT_COMMANDS_TEST:
  .byte $42, 0
  .byte $43, $82, $07, $08
  .byte $00

INIT_COMMANDS:
  .byte $ef, 3, $03, $80, $02
  .byte $cf, 3, $00, $c1, $30
  .byte $ed, 4, $64, $03, $12, $81
  .byte $e8, 3, $85, $00, $78
  .byte $cb, 5, $39, $2c, $00, $34, $02
  .byte $f7, 1, $20
  .byte $ea, 2, $00, $00
  .byte ILI9341_PWCTR1   , 1, $23             ; Power control VRH[5:0]
  .byte ILI9341_PWCTR2   , 1, $10             ; Power control SAP[2:0];BT[3:0]
  .byte ILI9341_VMCTR1   , 2, $3e, $28        ; VCM control
  .byte ILI9341_VMCTR2   , 1, $86             ; VCM control2
  .byte ILI9341_MADCTL   , 1, $48             ; Memory Access Control
  .byte ILI9341_VSCRSADD , 1, $00             ; Vertical scroll zero
  .byte ILI9341_PIXFMT   , 1, $55
  .byte ILI9341_FRMCTR1  , 2, $00, $18
  .byte ILI9341_DFUNCTR  , 3, $08, $82, $27   ; Display Function Control
  .byte $f2, 1, $00                           ; 3Gamma Function Disable
  .byte ILI9341_GAMMASET , 1, $01             ; Gamma curve selected
  .byte ILI9341_GMCTRP1  , 15, $0f, $31, $2b, $0c, $0e, $08 ; Set Gamma
  .byte   $4e, $f1, $37, $07, $10, $03, $0e, $09, $00
  .byte ILI9341_GMCTRN1  , 15, $00, $0e, $14, $03, $11, $07 ; Set Gamma
  .byte   $31, $c1, $48, $08, $0f, $0c, $31, $36, $0f
  .byte ILI9341_SLPOUT   , $80                ; Exit Sleep
  .byte ILI9341_DISPON   , $80                ; Display on
  .byte $00                                   ; End of list

