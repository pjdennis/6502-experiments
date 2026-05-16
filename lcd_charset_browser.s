; lcd_charset_browser.s -- 5x8 / 2-line charset browser.
;
; Pages through codes 0x20..0xFF showing 32 at a time (16 per line on
; the wendy2c 16x2 LCD), advancing to the next page on each debounced
; press of the control button. Wraps from the last page back to page 0.
;
; The button (CONTROL_BUTTON on PORTA bit 1) is active-low. We wait
; for it to be debounced "up" before sampling for a fresh press, then
; debounce again on release so a held button doesn't burn through the
; pages.

  .include base_config_wendy2c.inc

DISPLAY_STRING_PARAM = $00 ; 2 bytes (unused, reserved by display_string.inc)

CONTROL_BUTTON      = %00000010
CONTROL_BUTTON_PORT = PORTA

PAGE_START = $20            ; first printable code
PAGE_COUNT = 7              ; 7 pages * 32 chars = 0x20..0xFF
CHARS_PER_PAGE = 32

PAGE_NUM = $02              ; zero-page byte: current page 0..PAGE_COUNT-1

  .org $4000
  jmp program_entry

  .include delay_routines.inc
  .include display_routines_4bit.inc

program_entry:
  ; Configure the control button pin as input.
  lda #CONTROL_BUTTON
  trb CONTROL_BUTTON_PORT + DDR_OFFSET

  jsr reset_display
  lda #(CMD_DISPLAY_ON_OFF_CONTROL | CMD_PARAM_DISPLAY_ON)
  jsr display_command

  stz PAGE_NUM
.page_loop:
  jsr show_page
  jsr wait_button_press_debounced

  inc PAGE_NUM
  lda PAGE_NUM
  cmp #PAGE_COUNT
  bne .page_loop
  stz PAGE_NUM
  bra .page_loop


; show_page -- render PAGE_NUM's 32 characters: 16 on line 1, 16 on
; line 2. Character codes run PAGE_START + PAGE_NUM*32 + 0..31.
show_page:
  jsr clear_display

  ; X tracks the next char to display. Start at PAGE_START + PAGE_NUM*32.
  lda PAGE_NUM
  asl
  asl
  asl
  asl
  asl                          ; A = PAGE_NUM * 32
  clc
  adc #PAGE_START
  tax

  ldy #16
.line1:
  txa
  jsr display_character
  inx
  dey
  bne .line1

  lda #(CMD_SET_DDRAM_ADDRESS | DISPLAY_SECOND_LINE)
  jsr display_command

  ldy #16
.line2:
  txa
  jsr display_character
  inx
  dey
  bne .line2

  rts


; wait_button_press_debounced --
;   1. wait for the button to read debounced-up (in case it's still
;      held from the previous page)
;   2. wait for the next press edge
;   3. wait for the release to debounce, so a held button doesn't
;      auto-advance multiple pages.
wait_button_press_debounced:
  jsr wait_button_up_debounced
  jsr wait_button_down
  jsr wait_button_up_debounced
  rts


; wait_button_down -- spin until the button is pressed (active-low).
wait_button_down:
  lda CONTROL_BUTTON_PORT
  and #CONTROL_BUTTON
  bne wait_button_down
  rts


; wait_button_up_debounced -- require 5 consecutive 10ms reads of "up"
; before returning. Mirrors shift_in_test.s's wait_for_button_up.
wait_button_up_debounced:
  phx
  phy
.outer:
  ldy #5
.inner:
  lda #1
  jsr delay_hundredths         ; 10ms (1/100 s)
  lda CONTROL_BUTTON_PORT
  and #CONTROL_BUTTON
  beq .outer                   ; pressed -> reset the debounce window
  dey
  bne .inner
  ply
  plx
  rts
