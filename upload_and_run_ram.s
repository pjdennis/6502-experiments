ORIGIN            = $2000
UPLOAD_TO         = $3000
UPLOAD_RAM        = 1


  .include upload_and_run.inc


ready_message: asciiz 'Ready (RAM).'


;initialize_restart_handler:
;  ; Point interrupt handler to reset routine
;  lda #$4c                       ; jmp opcode
;  sta INTERRUPT_ROUTINE
;  lda #<reset_interrupt
;  sta INTERRUPT_ROUTINE + 1
;  lda #>reset_interrupt
;  sta INTERRUPT_ROUTINE + 2
;
;  ; Configure and enable CA2 independent interrupts
;  lda #PCR_CA2_IND_NEG_E
;  sta PCR
;  lda #(IERSETCLEAR | ICA2)
;  sta IER
;  rts


; Triggered by CA2 negative edge
;reset_interrupt:
;  ; Clear and reset CA2 interrupts
;  lda #0
;  sta PCR
;  lda #ICA2
;  sta IER
;  sta IFR
;
; Wait for restart button up
;wait_for_restart_button_up_outer_loop:
;  ldy #5
;wait_for_restart_button_up_inner_loop:
;  lda #100
;  jsr delay_10_thousandths
;  lda PORTA
;  and #SERIAL_IN
;  beq wait_for_restart_button_up_outer_loop
;  dey
;  bne wait_for_restart_button_up_inner_loop
;
;  jmp program_start
