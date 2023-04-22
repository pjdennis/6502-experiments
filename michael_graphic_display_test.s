  .include base_config_v2.inc

DISPLAY_STRING_PARAM = $00 ; 2 bytes
GD_ZERO_PAGE_BASE    = $02

GD_CHAR_BUFFER           = $0300 ; GD_CHAR_ROWS * GD_CHAR_COLS bytes (e.g. 20 * 20 = 400)
GD_CHAR_TEMP             = GD_CHAR_BUFFER + GD_CHAR_BUFFER_SIZE

  .org $2000
  jmp initialize_machine

  ; Place code for delay_routines at start of page to ensure no page boundary crossings
  ; during timing loops
  .include delay_routines.inc

  .include initialize_machine_v2.inc
  .include display_routines.inc
  .include display_string.inc
  .include graphics_display.inc

program_start:
  ldx #$ff ; Initialize stack
  txs

  jsr gd_configure

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

  jsr gd_clear_screen

  lda #0
  sta GD_ROW
  lda #0
  sta GD_COL
  lda #<hello_message
  sta GD_STRING_PTR
  lda #>hello_message
  sta GD_STRING_PTR + 1
  jsr gd_show_string  
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
  sta GD_COLOR
  lda #>ILI9341_RED
  sta GD_COLOR + 1
  jsr send_stripe
  lda #<ILI9341_WHITE
  sta GD_COLOR
  lda #>ILI9341_WHITE
  sta GD_COLOR + 1
  jsr send_stripe
  lda #<ILI9341_ORANGE
  sta GD_COLOR
  lda #>ILI9341_ORANGE
  sta GD_COLOR + 1
  jsr send_stripe
  lda #<ILI9341_NAVY
  sta GD_COLOR
  lda #>ILI9341_NAVY
  sta GD_COLOR + 1
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
  lda GD_COLOR + 1
;  jsr gd_send_data
  sta PORTB
  lda #GD_E
  tsb GD_PORT
  trb GD_PORT

  lda GD_COLOR
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
