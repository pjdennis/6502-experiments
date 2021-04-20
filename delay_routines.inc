; Can support clock frequency up to 10 MHz before overflowing these values
D_10_TH_1 = CLOCK_FREQ_KHZ / 1000 * 20 - 8
D_10_TH_2 = CLOCK_FREQ_KHZ / 1000 * 20 - 2

; On entry A = delay in 100ths of a second
; On exit A, X, Y are preserved
delay_hundredths:
  pha
  phx
  tax
  lda #100
delay_hundredths_loop:
  cpx #0
  beq delay_hundredths_done
  jsr delay_10_thousandths
  dex
  bra delay_hundredths_loop
delay_hundredths_done:
  plx
  pla
  rts


; On entry A = delay in 10 thousandths of a second
; On exit  A, X and Y are preserved
delay_10_thousandths: ; 6 cycles* (assuming jsr to the routine)
  cmp #0              ; 2 cycles*
  beq delay_exit      ; 2 cycles* (if branch does not succeed)
  phx                 ; 3 cycles*
  phy                 ; 3 cycles*
  tax                 ; 2 cycles*

  ; Delay goes here to make the balance of the first 100 cycles
  ; 100 cycles per iteration of outer_delay
  ; 5 cycles to get out of outer_delay
  ; 34 cycles outside of inner loop (*)
  ; 34 + 5 = 39 cycles accounted for from the 100
  ; 100 - 39 = 61 additional cycles needed to make the first 10 thousandth
  ; 5 cycles per iteration of inner loop
  ; 61 / 5 = 12.2 iterations
  ; 12 iterations = 11 * 5 + 4 = 59 cycles
  ; extra delay = 61 - 59 = 2 cycles
  ; double delay: 200 - 39 = 161 additional cycles
  ; 161 / 5 = 32.2 iterations
  ; 32 iterations = 31 * 5 + 4 = 159 cycles
  ; extra delay = 161 - 159 = 2 cycles

  nop                 ; 2 cycles (extra delay)
  ldy #D_10_TH_1      ; 2 cycles*  ; 12 (1 MHz) or 32 (2 MHz)
inner_delay_0:        ; Per iteration: 5 cycles; 4 on last
  dey                 ; 2 cycles
  bne inner_delay_0   ; 3 cycles or 2 if branch not taken

outer_delay:          ; looking to have 100 cycles per iteration
  dex                 ; 2 cycles
  beq delay_done      ; 2 cycles or 3 if branch taken

  ; 9 cycles outside of inner loop (excluding extra delay)
  ; need total of 100 - 9 = 91 extra cycles
  ; 91 / 5 = 18.2 iterations
  ; 18 iterations = 17 * 5 + 4 = 89 cycles
  ; extra delay = 91 - 89 = 2 cycles
  ; double delay: 200 - 9 = 191 extra cycles
  ; 191 / 5 = 38.2 iterations
  ; 38 iterations = 37 * 5 + 4 = 189 cycles
  ; extra delay = 191 - 189 = 2 cycles

  nop                 ; 2 cycles (extra delay)
  ldy #D_10_TH_2      ; 2 cycles  ; 18 (1 MHz) or 38 (2 MHz)
inner_delay:          ; Per iteration: 5 cycles; 4 on last
  dey                 ; 2 cycles
  bne inner_delay     ; 3 cycles or 2 if branch not taken

  bra outer_delay     ; 3 cycles

delay_done:
  ply                 ; 4 cycles*
  plx                 ; 4 cycles*
delay_exit:
  rts                 ; 6 cycles*
