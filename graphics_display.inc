  .include character_patterns_12x16.inc

; PORT A
GD_PORT = PORTA

GD_E    = %00000001
GD_CSB  = %00000010
GD_RSTB = %00000100
GD_DC   = %00100000

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

CHAR_ROWS = 20
CHAR_COLS = 20

GD_CMD_PTR           = GD_ZERO_PAGE_BASE + $00 ; 2 bytes
GD_COLOR             = GD_ZERO_PAGE_BASE + $02 ; 2 bytes
GD_ROW               = GD_ZERO_PAGE_BASE + $04 ; 1 byte
GD_COL               = GD_ZERO_PAGE_BASE + $05 ; 1 byte
GD_X                 = GD_ZERO_PAGE_BASE + $06 ; 2 bytes
GD_Y                 = GD_ZERO_PAGE_BASE + $08 ; 2 bytes
GD_TEMP              = GD_ZERO_PAGE_BASE + $0a ; 2 bytes
GD_CHAR_DATA_PTR     = GD_ZERO_PAGE_BASE + $0c ; 2 bytes
GD_STRING_PTR        = GD_ZERO_PAGE_BASE + $0e ; 2 bytes
GD_BYTE              = GD_ZERO_PAGE_BASE + $10 ; 1 byte


gd_configure:
  lda #GD_E
  trb PORTA
  lda #GD_RSTB | GD_CSB
  tsb PORTA
  lda #GD_E | GD_RSTB | GD_CSB
  tsb DDRA
  rts


gd_select:
  pha
  lda #GD_DC
  tsb GD_PORT
  tsb GD_PORT + DDR_OFFSET
  lda #GD_CSB
  trb GD_PORT
  pla
  rts


gd_unselect:
  pha
  lda #GD_CSB
  tsb GD_PORT
  lda #GD_DC
  trb GD_PORT
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
  lda #GD_DC
  trb GD_PORT
  pla
  jsr gd_send_data
  lda #GD_DC
  tsb GD_PORT
  rts


gd_send_data:
  sta PORTB
  lda #GD_E
  tsb GD_PORT
  trb GD_PORT
  rts


gd_clear_screen:
  lda #ILI9341_DISPOFF
  jsr gd_send_command

  lda #ILI9341_CASET
  jsr gd_send_command
  lda #0
  jsr gd_send_data
  lda #0
  jsr gd_send_data
  lda #>(ILI9341_TFTHEIGHT - 1)
  jsr gd_send_data
  lda #<(ILI9341_TFTHEIGHT - 1)
  jsr gd_send_data

  lda #ILI9341_PASET
  jsr gd_send_command
  lda #0
  jsr gd_send_data
  lda #0
  jsr gd_send_data
  lda #>(ILI9341_TFTWIDTH - 1)
  jsr gd_send_data
  lda #<(ILI9341_TFTWIDTH - 1)
  jsr gd_send_data

  lda #ILI9341_RAMWR
  jsr gd_send_command

  lda #0
  sta PORTB

LOOP_COUNT = -9600 ; 256 * 240 * 20 = 320 * 240 * 16 = 9600 * 16 * 8

  lda #<LOOP_COUNT
  sta GD_TEMP
  lda #>LOOP_COUNT
  sta GD_TEMP + 1

  lda GD_PORT
  and #~GD_E
  tax
  ldy #0
  ora #GD_E

.loop:
  sta PORTA,Y ;  1
  stx PORTA
  sta PORTA,Y ;  2
  stx PORTA
  sta PORTA,Y ;  3
  stx PORTA
  sta PORTA,Y ;  4
  stx PORTA
  sta PORTA,Y ;  5
  stx PORTA
  sta PORTA,Y ;  6
  stx PORTA
  sta PORTA,Y ;  7
  stx PORTA
  sta PORTA,Y ;  8
  stx PORTA
  sta PORTA,Y ;  9
  stx PORTA
  sta PORTA,Y ; 10
  stx PORTA
  sta PORTA,Y ; 11
  stx PORTA
  sta PORTA,Y ; 12
  stx PORTA
  sta PORTA,Y ; 13
  stx PORTA
  sta PORTA,Y ; 14
  stx PORTA
  sta PORTA,Y ; 15
  stx PORTA
  sta PORTA,Y ; 16
  stx PORTA

  inc GD_TEMP
  bne .loop
  inc GD_TEMP + 1
  bne .loop

  lda #ILI9341_DISPON
  jsr gd_send_command
  rts


gd_show_string:
  .loop:
  lda (GD_STRING_PTR)
  beq .done
  cmp #'\n'
  beq .newline
  jsr gd_show_character
  jsr gd_next_character
.continue:
  inc GD_STRING_PTR
  bne .loop
  inc GD_STRING_PTR + 1
  bne .loop
.done:
  rts
.newline
  stz GD_COL
  inc GD_ROW
  bra .continue


gd_show_character:
  jsr set_char_data_ptr
  jsr x_y_from_row_col

  lda #ILI9341_CASET
  jsr gd_send_command
  lda GD_Y + 1
  jsr gd_send_data
  lda GD_Y
  jsr gd_send_data

  clc
  lda GD_Y
  adc #15
  sta GD_Y
  lda GD_Y + 1
  adc #0
  sta GD_Y + 1

  lda GD_Y + 1
  jsr gd_send_data
  lda GD_Y
  jsr gd_send_data

  lda #ILI9341_PASET
  jsr gd_send_command
  lda GD_X + 1
  jsr gd_send_data
  lda GD_X
  jsr gd_send_data

  clc
  lda GD_X
  adc #11
  sta GD_X
  lda GD_X + 1
  adc #0
  sta GD_X + 1

  lda GD_X + 1
  jsr gd_send_data
  lda GD_X
  jsr gd_send_data

  lda #ILI9341_RAMWR
  jsr gd_send_command

  ldy #0
.col_loop:
  lda (GD_CHAR_DATA_PTR),Y
; show column
  sta GD_BYTE
  ldx #8
.row_loop:
  lsr GD_BYTE
  bcc .low_bit
; high bit
  lda #>ILI9341_BLUE
;  jsr gd_send_data
  sta PORTB
  lda #GD_E
  tsb GD_PORT
  trb GD_PORT
  lda #<ILI9341_BLUE
;  jsr gd_send_data
  sta PORTB
  lda #GD_E
  tsb GD_PORT
  trb GD_PORT
  bra .color_done
.low_bit:
  lda #>ILI9341_BLACK
;  jsr gd_send_data
  sta PORTB
  lda #GD_E
  tsb GD_PORT
  trb GD_PORT
;  lda #<ILI9341_BLACK
;;  jsr gd_send_data
;  sta PORTB
;  lda #GD_E
  tsb GD_PORT
  trb GD_PORT
.color_done:
  dex
  bne .row_loop
  iny
  cpy #24
  bne .col_loop
  rts


gd_next_character:
  lda GD_COL
  inc
  cmp #CHAR_COLS
  beq .next_row
  sta GD_COL
  rts
.next_row:
  stz GD_COL
  inc GD_ROW
  rts


set_char_data_ptr:
  ; calculate character offset
  sec
  sbc #' '

  ; GD_CHAR_DATA_PTR = character offset * 24 = co * 16 + co * 8
  sta GD_TEMP
  lsr
  lsr
  lsr
  lsr
  sta GD_TEMP + 1
  lsr
  sta GD_CHAR_DATA_PTR + 1
  lda GD_TEMP
  asl
  asl
  asl
  sta GD_CHAR_DATA_PTR
  asl
  ;sta GD_TEMP
  clc
  ;lda GD_TEMP
  adc GD_CHAR_DATA_PTR
  sta GD_CHAR_DATA_PTR
  lda GD_TEMP + 1
  adc GD_CHAR_DATA_PTR + 1
  sta GD_CHAR_DATA_PTR + 1

  ; Add the table base address
  clc
  lda GD_CHAR_DATA_PTR
  adc #<character_patterns_12x16
  sta GD_CHAR_DATA_PTR
  lda GD_CHAR_DATA_PTR + 1
  adc #>character_patterns_12x16
  sta GD_CHAR_DATA_PTR + 1
  rts


x_y_from_row_col:
  ; GD_Y = GD_ROW * 16
  lda GD_ROW
  lsr
  lsr
  lsr
  lsr
  sta GD_Y + 1
  lda GD_ROW
  asl
  asl
  asl
  asl
  sta GD_Y
  ; GD_X = GD_COL * 12 = GD_COL * 8 + GD_COL * 4
  lda GD_COL
  rol
  rol
  rol
  rol
  and #$07
  sta GD_TEMP + 1
  lsr
  sta GD_X + 1
  lda GD_COL
  asl
  asl
  sta GD_X
  asl
  ;sta GD_TEMP
  clc
  ;lda GD_TEMP
  adc GD_X
  sta GD_X
  lda GD_TEMP + 1
  adc GD_X + 1
  sta GD_X + 1
  rts


gd_initialize:
  pha
  phx
  phy
  lda #<INIT_COMMANDS
  sta GD_CMD_PTR
  lda #>INIT_COMMANDS
  sta GD_CMD_PTR + 1
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
  lda (GD_CMD_PTR)
  inc GD_CMD_PTR
  bne .next_byte_over
  inc GD_CMD_PTR + 1
.next_byte_over:
  rts
.delay:
  lda #15
  jsr delay_hundredths
  rts


INIT_COMMANDS:
  .byte $ef,              3, $03, $80, $02
  .byte $cf,              3, $00, $c1, $30
  .byte $ed,              4, $64, $03, $12, $81
  .byte $e8,              3, $85, $00, $78
  .byte $cb,              5, $39, $2c, $00, $34, $02
  .byte $f7,              1, $20
  .byte $ea,              2, $00, $00
  .byte ILI9341_PWCTR1,   1, $23                     ; Power control VRH[5:0]
  .byte ILI9341_PWCTR2,   1, $10                     ; Power control SAP[2:0];BT[3:0]
  .byte ILI9341_VMCTR1,   2, $3e, $28                ; VCM control
  .byte ILI9341_VMCTR2,   1, $86                     ; VCM control2
  .byte ILI9341_MADCTL,   1, $48                     ; Memory Access Control
  .byte ILI9341_VSCRSADD, 1, $00                     ; Vertical scroll zero
  .byte ILI9341_PIXFMT,   1, $55
  .byte ILI9341_FRMCTR1,  2, $00, $18
  .byte ILI9341_DFUNCTR,  3, $08, $82, $27           ; Display Function Control
  .byte $f2,              1, $00                     ; 3Gamma Function Disable
  .byte ILI9341_GAMMASET, 1, $01                     ; Gamma curve selected
  .byte ILI9341_GMCTRP1, 15, $0f, $31, $2b, $0c, $0e ; Set Gamma
  .byte                      $08, $4e, $f1, $37, $07
  .byte                      $10, $03, $0e, $09, $00
  .byte ILI9341_GMCTRN1, 15, $00, $0e, $14, $03, $11 ; Set Gamma
  .byte                      $07, $31, $c1, $48, $08
  .byte                      $0f, $0c, $31, $36, $0f
  .byte ILI9341_SLPOUT, $80                          ; Exit Sleep
  .byte ILI9341_DISPON,   0                          ; Display on
  .byte $00                                          ; End of list
