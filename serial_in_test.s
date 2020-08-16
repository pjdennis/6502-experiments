  .include base_config_v1.inc

BUTTON            = %00100000
SH_OUT_DATA       = %01000000
SH_OUT_CLOCK      = %00010000

HALF_BIT_INTERVAL = 104 ; 2 MHz 9600 bps 

IO_PINS_MASK_A    = BUTTON | SH_OUT_DATA | SH_OUT_CLOCK | SERIAL_IN

SH_IN_CLOCK       = %10000000

IO_PINS_MASK_B    = SH_IN_CLOCK

D_S_I_P           = $00    ; Two bytes
CP_M_DEST_P       = $02    ; Two bytes
CP_M_SRC_P        = $04    ; Two bytes
CP_M_LEN          = $06    ; Two bytes
TEMP              = $08
TRANSFER_STARTED  = $09

TRANSLATE         = $200

INTERRUPT_ROUTINE = $3f00

  .org $2000
  jmp program_entry

  .include display_update_routines.inc
  .include display_hex.inc
  .include display_binary.inc
  .include display_string_immediate.inc
  .include delay_routines.inc
  .include copy_memory.inc

program_entry:
  lda #$00
  sta IER

  lda #SH_OUT_CLOCK
  tsb PORTA

  lda DDRA
  and #(~IO_PINS_MASK_A & $ff)
  ora #(SH_OUT_DATA | SH_OUT_CLOCK)
  sta DDRA

  lda #SH_IN_CLOCK
  tsb PORTB

  lda DDRB
  and #(~IO_PINS_MASK_B & $ff)
  ora #(SH_IN_CLOCK)
  sta DDRB

  ; Clear out the LEDs
  lda #ACR_SR_IN_CK
  sta ACR
  lda #0
  jsr send_via_io_pins

  ; Build serial data translation table
  jsr build_translate

  ; Relocate the interrupt handler
  lda #<INTERRUPT_ROUTINE
  sta CP_M_DEST_P
  lda #>INTERRUPT_ROUTINE
  sta CP_M_DEST_P + 1
  lda #<interrupt
  sta CP_M_SRC_P
  lda #>interrupt
  sta CP_M_SRC_P + 1
  lda #<(interrupt_end - interrupt)
  sta CP_M_LEN
  lda #>(interrupt_end - interrupt)
  sta CP_M_LEN + 1
  jsr copy_memory
 
main_loop:
  jsr clear_display 
  jsr display_string_immediate
  .asciiz "Waiting for data"

  stz TRANSFER_STARTED

  lda #ACR_SR_IN_T2
  sta ACR

  lda #PCR_CB2_IND_NEG_E
  sta PCR

  lda #ICB2
  sta IFR

  lda #(IERSETCLEAR | ICB2)
  sta IER

data_wait_loop:
  lda TRANSFER_STARTED
  beq data_wait_loop
 
  jsr wait_for_button_up
  jsr clear_display
  jsr display_string_immediate
  .asciiz "Press to show"

  jsr wait_for_button_down
  jsr clear_display
  jsr display_string_immediate
  .asciiz "Rec: "
  lda SR
  tax
  jsr display_binary

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  jsr display_string_immediate
  .asciiz "Tra: "
  txa
  jsr translate
  jsr display_binary


  jmp stop_here


  jsr wait_for_button_up

  jsr wait_for_button_down

  jmp main_loop 


interrupt:
  pha

  lda IFR
  and #ICB2
  bne interrupt_serial_in_start
  ;TODO check for other interrupt types

  bra interrupt_done
interrupt_serial_in_start:
  lda #0
  sta PCR

  lda #(HALF_BIT_INTERVAL * 2) - 2 - 10 - 12  ; 2
  sta T2CL                                    ; 4
  lda #0                                      ; 2
  sta T2CH                                    ; 4

  lda #(HALF_BIT_INTERVAL - 2)
  sta T2CL

  lda SR   ; Start shifting

  lda #ICB2
  sta IFR
  sta IER

  inc TRANSFER_STARTED

interrupt_done:
  pla
  rti

interrupt_end:


send_via_io_pins:
  pha
  phx
  phy

  ldy #8
send_via_io_pins_loop:

  asl
  tax
  bcs send_via_io_pins_one
; send a zero
;  jsr wait_for_button_down
  lda #SH_OUT_DATA
  trb PORTA
;  jsr wait_for_button_up

;  jsr wait_for_button_down
  lda #SH_OUT_CLOCK
  trb PORTA
;  jsr wait_for_button_up

;  jsr wait_for_button_down
  tsb PORTA
;  jsr wait_for_button_up

  bra send_via_io_pins_continue

send_via_io_pins_one
; send a one
;  jsr wait_for_button_down
  lda #SH_OUT_DATA
  tsb PORTA
;  jsr wait_for_button_up

;  jsr wait_for_button_down
  lda #SH_OUT_CLOCK
  trb PORTA
;  jsr wait_for_button_up

;  jsr wait_for_button_down
  tsb PORTA
;  jsr wait_for_button_up

send_via_io_pins_continue:
  txa
  dey
  bne send_via_io_pins_loop

  ply
  plx
  pla
  rts


shift_in_using_cb2:
  pha
  phx

  ldx #8
shift_in_loop:
  jsr wait_for_button_down
  lda #SH_IN_CLOCK
  trb PORTB
  jsr clear_display
  jsr display_string_immediate
  .asciiz "Clock low"
  jsr wait_for_button_up

  jsr wait_for_button_down
  lda #SH_IN_CLOCK
  tsb PORTB
  jsr clear_display
  jsr display_string_immediate
  .asciiz "Clock high"
  jsr wait_for_button_up

  dex
  bne shift_in_loop

  plx
  pla
  rts


send_serial_with_delay:
  jsr send_serial
  jsr delay
  rts


send_serial:
  pha
  ;lda #$00
  ;sta T2CL
  ;lda #ACR_SR_OUT_T2
  lda #ACR_SR_OUT_CK
  sta ACR
  pla
  sta SR
  rts


delay:
  pha
  phx

  ldx #20
  lda #100
delay_loop:
  jsr delay_10_thousandths
  dex
  bne delay_loop

  plx
  pla
  rts


short_delay:
  pha
  phx

  ldx #2
  lda #100
short_delay_loop:
  jsr delay_10_thousandths
  dex
  bne short_delay_loop

  plx
  pla
  rts


wait_for_button_down:
  pha
wait_for_button_down_loop:
  lda PORTA
  and #BUTTON
  bne wait_for_button_down_loop
  pla
  rts


wait_for_button_up:
  pha
  phy
wait_for_button_up_outer_loop:
  ldy #5
wait_for_button_up_inner_loop:
  lda #100
  jsr delay_10_thousandths
  lda PORTA
  and #BUTTON
  beq wait_for_button_up_outer_loop
  dey
  bne wait_for_button_up_inner_loop
  ply
  pla
  rts

translate:
  phx
  tax
  lda TRANSLATE,X
  plx
  rts


build_translate:
  pha
  phx
  phy

  ldx #0
build_translate_loop:
  txa
  ldy #8
build_translate_shift_loop: 
  asl
  ror TEMP
  dey
  bne build_translate_shift_loop
  
  lda TEMP
  sta TRANSLATE,X

  inx
  bne build_translate_loop

  ply
  plx
  pla
  rts


stop_here:
  bra stop_here
