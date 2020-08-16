  .include base_config_v1.inc

BPS_HUNDREDS     = 96
;PBS_HUNDREDS      = 384

HALF_BIT_INTERVAL = CLOCK_FREQ_KHZ * 5 / BPS_HUNDREDS

D_S_I_P           = $00    ; Two bytes
CP_M_DEST_P       = $02    ; Two bytes
CP_M_SRC_P        = $04    ; Two bytes
CP_M_LEN          = $06    ; Two bytes
UPLOAD_P          = $08    ; Two bytes
WAITING_FOR_SHIFT = $0a
TEMP              = $0b

TRANSLATE         = $200
UPLOAD_TO         = $3000
INTERRUPT_ROUTINE = $3f00

  .org $2000
  jmp program_entry

  .include display_update_routines.inc
  .include display_binary.inc
  .include display_string_immediate.inc
  .include copy_memory.inc

program_entry:
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
 
  ; Wait for data
  jsr clear_display 
  jsr display_string_immediate
  .asciiz "Wait for start"

  stz WAITING_FOR_SHIFT

  lda #<UPLOAD_TO
  sta UPLOAD_P
  lda #>UPLOAD_TO
  sta UPLOAD_P + 1

  lda #ACR_SR_IN_T2
  sta ACR

  lda #PCR_CB2_IND_NEG_E
  sta PCR

  lda #ICB2
  sta IFR
  lda #(IERSETCLEAR | ICB2)
  sta IER

wait_for_end:
  lda UPLOAD_P + 1
  cmp #>(UPLOAD_TO + 2)
  bcc wait_for_end
  bne at_end
  lda UPLOAD_P
  cmp #<(UPLOAD_TO + 2)
  bcc wait_for_end
at_end:
  ; Now we have received two bytes

  jsr clear_display
  jsr display_string_immediate
  .asciiz "B1: "
  lda UPLOAD_TO
  jsr display_binary

  lda #DISPLAY_SECOND_LINE
  jsr move_cursor
  jsr display_string_immediate
  .asciiz "B2: "
  lda UPLOAD_TO + 1
  jsr display_binary

stop_here:
  bra stop_here
  

interrupt:
  pha

  lda WAITING_FOR_SHIFT
  bne interrupt_shift_done

interrupt_serial_in_start:
  lda #(HALF_BIT_INTERVAL * 2 - 2 - 20 - 10)  ; 2
  sta T2CL                                    ; 4
  stz T2CH                                    ; 4

  lda #(HALF_BIT_INTERVAL - 2)
  sta T2CL

  lda SR   ; Start shifting

  inc WAITING_FOR_SHIFT
  
  lda #ICB2
  sta IER

  lda #(IERSETCLEAR | ISR)
  sta IER

  bra interrupt_done

interrupt_shift_done:
  phx
  ldx SR                                      ; Clears interrupt
  lda #ACR_SR_IN_T2
  stz ACR
  sta ACR
  lda TRANSLATE,X
  plx
  sta (UPLOAD_P)
  inc UPLOAD_P
  bne interrupt_upload_incremented
  inc UPLOAD_P + 1
interrupt_upload_incremented:
  dec WAITING_FOR_SHIFT

  lda #ICB2
  sta IFR
  lda #(IERSETCLEAR | ICB2)
  sta IER

interrupt_done:
  pla
  rti
interrupt_end:


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
