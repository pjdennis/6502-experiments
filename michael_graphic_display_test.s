  .include base_config_v2.inc

; PORT A
GD_PORT = PORTA

GD_E    = %00000001
GD_CSB  = %00000010
GD_RSTB = %00000100
GD_DC   = %00100000

; Dummy for the unused code
GD_MOSI = 0
GD_MISO = 0
GD_CLK  = 0

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
COUNTER               = $12 ; 2 bytes
BYTE                  = $14 ; 1 byte

  .org $2000
  jmp initialize_machine

  ; Place code for delay_routines at start of page to ensure no page boundary crossings
  ; during timing loops
  .include delay_routines.inc

  .include initialize_machine_v2.inc
  .include display_routines.inc
  .include display_hex.inc
  .include display_string.inc
  .include character_patterns_12x16.inc

program_start:
  ldx #$ff ; Initialize stack
  txs

  lda #GD_E
  trb PORTA
  lda #GD_RSTB | GD_CSB
  tsb PORTA
  lda #GD_E | GD_RSTB | GD_CSB
  tsb DDRA

  jsr clear_display

  lda #<start_message
  ldx #>start_message
  jsr display_string

  jsr gd_select
  jsr gd_reset
  jsr gd_initialize
  jsr gd_unselect

;  jsr gd_select
;  jsr show_content
;  jsr gd_unselect


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


start_message:  asciiz "Starting..."
done_message:   asciiz "Done."
hello_message:  asciiz "Hello, World! The\nquick brown fox\njumps over the lazy dog.\n\n\n   Phil\n        (\\/)\n         \\/\n             Angel"


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

  lda #0
  sta PORTB

LOOP_COUNT = -9600 ; 256 * 240 * 20 = 320 * 240 * 16 = 9600 * 16 * 8

  lda #<LOOP_COUNT
  sta COUNTER
  lda #>LOOP_COUNT
  sta COUNTER + 1

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

  inc COUNTER
  bne .loop
  inc COUNTER + 1
  bne .loop

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
; show column
  sta BYTE
  ldx #8
.row_loop:
  lsr BYTE
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
  and #$07
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
.height_loop:
  ldx #ILI9341_TFTWIDTH
.width_loop:
  lda COLOR + 1
;  jsr gd_send_data
  sta PORTB
  lda #GD_E
  tsb GD_PORT
  trb GD_PORT

  lda COLOR
;  jsr gd_send_data
  sta PORTB
  lda #GD_E
  tsb GD_PORT
  trb GD_PORT

  dex
  bne .width_loop
  dey
  bne .height_loop
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
  .byte $ef,               3, $03, $80, $02
  .byte $cf,               3, $00, $c1, $30
  .byte $ed,               4, $64, $03, $12, $81
  .byte $e8,               3, $85, $00, $78
  .byte $cb,               5, $39, $2c, $00, $34, $02
  .byte $f7,               1, $20
  .byte $ea,               2, $00, $00
  .byte ILI9341_PWCTR1,    1, $23                     ; Power control VRH[5:0]
  .byte ILI9341_PWCTR2,    1, $10                     ; Power control SAP[2:0];BT[3:0]
  .byte ILI9341_VMCTR1,    2, $3e, $28                ; VCM control
  .byte ILI9341_VMCTR2,    1, $86                     ; VCM control2
  .byte ILI9341_MADCTL,    1, $48                     ; Memory Access Control
  .byte ILI9341_VSCRSADD,  1, $00                     ; Vertical scroll zero
  .byte ILI9341_PIXFMT,    1, $55
  .byte ILI9341_FRMCTR1,   2, $00, $18
  .byte ILI9341_DFUNCTR,   3, $08, $82, $27           ; Display Function Control
  .byte $f2,               1, $00                     ; 3Gamma Function Disable
  .byte ILI9341_GAMMASET,  1, $01                     ; Gamma curve selected
  .byte ILI9341_GMCTRP1,  15, $0f, $31, $2b, $0c, $0e ; Set Gamma
  .byte                       $08, $4e, $f1, $37, $07
  .byte                       $10, $03, $0e, $09, $00
  .byte ILI9341_GMCTRN1,  15, $00, $0e, $14, $03, $11 ; Set Gamma
  .byte                       $07, $31, $c1, $48, $08
  .byte                       $0f, $0c, $31, $36, $0f
  .byte ILI9341_SLPOUT,  $80                          ; Exit Sleep
  .byte ILI9341_DISPON,    0                          ; Display on
  .byte $00                                           ; End of list

