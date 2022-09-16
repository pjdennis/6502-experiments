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

CHAR_ROWS = 20
CHAR_COLS = 20


DISPLAY_STRING_PARAM  = $00 ; 2 bytes
CMD_PTR               = $02 ; 2 bytes
COLOR                 = $04 ; 2 bytes
ROW                   = $06 ; 1 byte
COL                   = $07 ; 1 byte
X                     = $08 ; 2 bytes
Y                     = $0a ; 2 bytes
TEMP                  = $0c ; 2 bytes
CHAR_DATA_PTR         = $0e ; 2 bytes
STRING_PTR            = $10 ; 2 bytes
PORT_VALUE            = $12 ; 1 byte

  .org $4000
  jmp program_entry

  ; Place code for delay_routines at start of page to ensure no page boundary crossings
  ; during timing loops
  .include delay_routines.inc

  .include display_routines_4bit.inc
  .include display_hex.inc
  .include display_string.inc
;  .include character_patterns_6x8.inc
  .include character_patterns_12x16.inc

program_entry:
  jsr clear_display


;  lda #20
;  sta ROW
;  lda #20
;  sta COL
;  jsr x_y_from_row_col
;  lda X + 1
;  jsr display_hex
;  lda X
;  jsr display_hex
;  lda #' '
;  jsr display_character
;  lda Y + 1
;  jsr display_hex
;  lda Y
;  jsr display_hex

;  lda #'~'
;  jsr set_char_data_ptr
;  lda CHAR_DATA_PTR + 1
;  jsr display_hex
;  lda CHAR_DATA_PTR
;  jsr display_hex

;  stp


  lda #<config_message
  ldx #>config_message
  jsr display_string

  jsr gd_select
  jsr gd_reset
  jsr gd_initialize
  jsr gd_unselect

;  jsr gd_select
;  lda #ILI9341_RDMADCTL
;  jsr gd_send_command
;  jsr gd_receive_data
;  jsr gd_unselect
;  jsr display_hex

;  jsr gd_select
;  lda #ILI9341_RDMODE 
;  jsr gd_send_command
;  jsr gd_receive_data
;  jsr gd_unselect
;  jsr display_hex


;  jsr gd_select
;  lda #ILI9341_RDSELFDIAG 
;  jsr gd_send_command
;  jsr gd_receive_data
;  jsr gd_unselect
;  jsr display_hex

;  jsr gd_select
;  lda #ILI9341_RDPIXFMT
;  jsr gd_send_command
;  jsr gd_receive_data
;  jsr gd_unselect
;  jsr display_hex

  jsr gd_select
  jsr show_content
  jsr gd_unselect

  stp

  jsr gd_select
; set screen orientation
  lda #ILI9341_MADCTL
  jsr gd_send_command
  lda #%10101000    ; original $48
  jsr gd_send_data

  jsr clear_screen

  lda #0
  sta ROW
  lda #0
  sta COL
  lda #<hello_message
  sta STRING_PTR
  lda #>hello_message
  sta STRING_PTR + 1
  jsr show_string  

  jsr gd_unselect

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  lda #<done_message
  ldx #>done_message
  jsr display_string

  stp


config_message: asciiz "Config:"
done_message:   asciiz "Done."
hello_message:  asciiz "Hello, World! The\nquick brown fox\njumps over the lazy dog.\n\n\n   Phil\n        (\\/)\n         \\/\n             Angel"

gd_select:
  pha
  lda #GD_CLK
  trb GD_PORT
  lda #GD_MOSI | GD_DC
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
  lda #GD_DC
  trb GD_PORT
  pla
  jsr gd_send_data
  lda #GD_DC
  tsb GD_PORT
  rts


gd_send_data:
  phx
  phy
  tay
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
;  lda #GD_CLK
;  tsb GD_PORT
;  trb GD_PORT
  inc GD_PORT
  dec GD_PORT

  dex
  bne .loop
  ply
  plx
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


clear_screen:
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

  lda #GD_MOSI
  trb GD_PORT

  lda GD_PORT
  sta PORT_VALUE
  ora #GD_CLK

; 256 * 240 * 20 = 320 * 240 * 16

  ldx #240
.outer_loop:
  ldy #0
  phx
  ldx PORT_VALUE
.inner_loop:
  sta GD_PORT ; 1
  stx GD_PORT
  sta GD_PORT ; 2
  stx GD_PORT
  sta GD_PORT ; 3
  stx GD_PORT
  sta GD_PORT ; 4
  stx GD_PORT
  sta GD_PORT ; 5
  stx GD_PORT
  sta GD_PORT ; 6
  stx GD_PORT
  sta GD_PORT ; 7
  stx GD_PORT
  sta GD_PORT ; 8
  stx GD_PORT
  sta GD_PORT ; 9
  stx GD_PORT
  sta GD_PORT ; 10
  stx GD_PORT
  sta GD_PORT ; 11
  stx GD_PORT
  sta GD_PORT ; 12
  stx GD_PORT
  sta GD_PORT ; 13
  stx GD_PORT
  sta GD_PORT ; 14
  stx GD_PORT
  sta GD_PORT ; 15
  stx GD_PORT
  sta GD_PORT ; 16
  stx GD_PORT
  sta GD_PORT ; 17
  stx GD_PORT
  sta GD_PORT ; 18
  stx GD_PORT
  sta GD_PORT ; 19
  stx GD_PORT
  sta GD_PORT ; 20
  stx GD_PORT
  dey
  bne .inner_loop
  plx
  dex
  beq .done
  jmp .outer_loop
.done:
  lda #ILI9341_DISPON
  jsr gd_send_command
  rts


show_string:
  .loop:
  lda (STRING_PTR)
  beq .done
  cmp #'\n'
  beq .newline
  jsr show_character
  jsr next_character
.continue:
  inc STRING_PTR
  bne .loop
  inc STRING_PTR + 1
  bne .loop
.done:
  rts
.newline
  stz COL
  inc ROW
  bra .continue

show_character:
  jsr set_char_data_ptr
  jsr x_y_from_row_col

  lda #ILI9341_CASET
  jsr gd_send_command
  lda Y + 1
  jsr gd_send_data
  lda Y
  jsr gd_send_data

  clc
  lda Y
  adc #15
  sta Y
  lda Y + 1
  adc #0
  sta Y + 1

  lda Y + 1
  jsr gd_send_data
  lda Y
  jsr gd_send_data

  lda #ILI9341_PASET
  jsr gd_send_command
  lda X + 1
  jsr gd_send_data
  lda X
  jsr gd_send_data

  clc
  lda X
  adc #11
  sta X
  lda X + 1
  adc #0
  sta X + 1

  lda X + 1
  jsr gd_send_data
  lda X
  jsr gd_send_data

  lda #ILI9341_RAMWR
  jsr gd_send_command

  ldy #0
.col_loop:
  lda (CHAR_DATA_PTR),Y
  jsr .show_column
  ;jsr .show_column
  iny
  cpy #24 ; was 6
  bne .col_loop
 
  rts
.show_column:
  pha
  ldx #8
.row_loop:
  lsr
  pha
  bcs .high_bit
; low bit
  lda #>ILI9341_BLACK
  jsr gd_send_data
  lda #<ILI9341_BLACK
  jsr gd_send_data
;  lda #>ILI9341_BLACK
;  jsr gd_send_data
;  lda #<ILI9341_BLACK
;  jsr gd_send_data
  bra .color_done
.high_bit:
  lda #>ILI9341_BLUE
  jsr gd_send_data
  lda #<ILI9341_BLUE
  jsr gd_send_data
;  lda #>ILI9341_BLUE
;  jsr gd_send_data
;  lda #<ILI9341_BLUE
;  jsr gd_send_data
.color_done:
  pla
  dex
  bne .row_loop
  pla
  rts


next_character:
  lda COL
  inc
  cmp #CHAR_COLS
  beq .next_row
  sta COL
  rts
.next_row:
  stz COL
  inc ROW
  rts


set_char_data_ptr:
  ; calculate character offset
  sec
  sbc #' '
  ;; CHAR_DATA_PTR = character offset * 6
  ;sta TEMP
  ;rol
  ;rol
  ;rol
  ;and #03
  ;sta TEMP + 1
  ;lsr
  ;sta CHAR_DATA_PTR + 1
  ;lda TEMP
  ;asl
  ;sta CHAR_DATA_PTR
  ;asl
  ;;sta TEMP
  ;clc
  ;;lda TEMP
  ;adc CHAR_DATA_PTR
  ;sta CHAR_DATA_PTR
  ;lda TEMP + 1
  ;adc CHAR_DATA_PTR + 1
  ;sta CHAR_DATA_PTR + 1

  ; CHAR_DATA_PTR = character offset * 24 = co * 16 + co * 8
  sta TEMP
  lsr
  lsr
  lsr
  lsr
  sta TEMP + 1
  lsr
  sta CHAR_DATA_PTR + 1
  lda TEMP
  asl
  asl
  asl
  sta CHAR_DATA_PTR
  asl
  ;sta TEMP
  clc
  ;lda TEMP
  adc CHAR_DATA_PTR
  sta CHAR_DATA_PTR
  lda TEMP + 1
  adc CHAR_DATA_PTR + 1
  sta CHAR_DATA_PTR + 1

  ; Add the table base address
  clc
  lda CHAR_DATA_PTR
  adc #<character_patterns_12x16
  sta CHAR_DATA_PTR
  lda CHAR_DATA_PTR + 1
  adc #>character_patterns_12x16
  sta CHAR_DATA_PTR + 1
  rts


x_y_from_row_col:
  ; Y = ROW * 16
  lda ROW
  lsr
  lsr
  lsr
  lsr
  sta Y + 1
  lda ROW
  asl
  asl
  asl
  asl
  sta Y
  ; X = COL * 12 = COL * 8 + COL * 4
  lda COL
  rol
  rol
  rol
  rol
  and #07
  sta TEMP + 1
  lsr
  sta X + 1
  lda COL
  asl
  asl
  sta X
  asl
  ;sta TEMP
  clc
  ;lda TEMP
  adc X
  sta X
  lda TEMP + 1
  adc X + 1
  sta X + 1
  rts


show_content:
  lda #ILI9341_CASET
  jsr gd_send_command
  lda #0
  jsr gd_send_data
  lda #0
  jsr gd_send_data
  lda #>(ILI9341_TFTWIDTH - 1)
  jsr gd_send_data
  lda #<(ILI9341_TFTWIDTH - 1)
  jsr gd_send_data

  lda #ILI9341_PASET
  jsr gd_send_command
  lda #0
  jsr gd_send_data
  lda #0
  jsr gd_send_data
  lda #>(ILI9341_TFTHEIGHT - 1)
  jsr gd_send_data
  lda #<(ILI9341_TFTHEIGHT - 1)
  jsr gd_send_data

  lda #ILI9341_RAMWR
  jsr gd_send_command

STRIPE_HEIGHT = 10

  ldy #ILI9341_TFTHEIGHT / STRIPE_HEIGHT / 4
.stripe_loop:
  lda #<ILI9341_RED
  sta COLOR
  lda #>ILI9341_RED
  sta COLOR + 1
  jsr send_stripe
  lda #<ILI9341_WHITE
  sta COLOR
  lda #>ILI9341_WHITE
  sta COLOR + 1
  jsr send_stripe
  lda #<ILI9341_ORANGE
  sta COLOR
  lda #>ILI9341_ORANGE
  sta COLOR + 1
  jsr send_stripe
  lda #<ILI9341_NAVY
  sta COLOR
  lda #>ILI9341_NAVY
  sta COLOR + 1
  jsr send_stripe
  dey
  bne .stripe_loop  
  rts


send_stripe:
  phy
  ldy #STRIPE_HEIGHT
.outer_loop:
  ldx #ILI9341_TFTWIDTH
.loop:
  lda COLOR + 1
  jsr gd_send_data
  lda COLOR
  jsr gd_send_data
  dex
  bne .loop
  dey
  bne .outer_loop
  ply
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
  .byte ILI9341_DISPON   , 0                  ; Display on
  .byte $00                                   ; End of list

