; Can support clock frequency up to 20 MHz before overflowing these values
D_10_TH_1 = CLOCK_FREQ_KHZ / (1000 / 10) - 4
D_10_TH_2 = CLOCK_FREQ_KHZ / (1000 / 10) - 1

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
delay_10_thousandths: ; 6 cycles assuming jsr to the routine  (e)
  cmp #0              ; 2 cycles                              (e)
  beq delay_exit      ; 2 cycles if branch does not succeed   (e)
  phx                 ; 3 cycles                              (e)
  phy                 ; 3 cycles                              (e)
  tax                 ; 2 cycles                              (e)

  ; Delay goes here to make the balance of the first 100 cycles
  ; 100 cycles per iteration of outer_delay
  ; 5 cycles to get out of outer_delay - (d)
  ; 34 cycles outside of inner loop - (e)
  ; 34 + 5 = 39 cycles accounted for from the 100
  ; 100 - 39 = 61 additional cycles needed to make the first 10 thousandth
  ; 10 cycles per iteration of inner loop - (f)
  ; 61 / 10 = 6.1 iterations
  ; 6 iterations = 5 * 10 + 9 = 59 cycles
  ; extra delay = 61 - 59 = 2 cycles - (g)
  ; double delay: 200 - 39 = 161 additional cycles
  ; 161 / 10 = 16.1 iterations
  ; 16 iterations = 15 * 10 + 9 = 159 cycles
  ; extra delay = 161 - 159 = 2 cycles - (g)

  nop                 ; 2 cycles (extra delay)                (g)
  ldy #D_10_TH_1      ; 2 cycles ; 6 (1 MHz) or 16 (2 MHz)    (e)
inner_delay_0:        ; Per iteration: 5 cycles; 4 on last - (f)
  nop                 ; 2 cycles                              (f)
  bra .nop_target_0   ; 3 cycles                              (f)
.nop_target_0:
  dey                 ; 2 cycles                              (f)
  bne inner_delay_0   ; 3 cycles or 2 if branch not taken     (f)

outer_delay:          ; looking to have 100 cycles per iteration
  dex                 ; 2 cycles                              (a)                    (d)
  beq delay_done      ; 2 cycles or 3 if branch taken         (a) - branch not taken (d) - branch taken

  ; 9 cycles outside of inner loop (excluding extra delay) - (a)
  ; need total of 100 - 9 = 91 extra cycles
  ; 91 / 10 = 9.1 iterations
  ; 9 iterations = 8 * 10 + 9 = 89 cycles
  ; extra delay = 91 - 89 = 2 cycles - (c)
  ; double delay: 200 - 9 = 191 extra cycles
  ; 191 / 10 = 19.1 iterations
  ; 19 iterations = 18 * 10 + 9 = 189
  ; extra delay = 191 - 189 = 2 cycles - (c)

  nop                 ; 2 cycles (extra delay)                (c)
  ldy #D_10_TH_2      ; 2 cycles ; 9 (1 MHz) or 19 (2 MHz)    (a)
inner_delay:          ; Per iteration: 10 cycles 9 on last - (b)
  nop                 ; 2 cycles                              (b)
  bra .nop_target     ; 3 cycles                              (b)
.nop_target:
  dey                 ; 2 cycles                              (b)
  bne inner_delay     ; 3 cycles or 2 if branch not taken     (b)

  bra outer_delay     ; 3 cycles                              (a)

delay_done:
  ply                 ; 4 cycles                              (e)
  plx                 ; 4 cycles                              (e)
delay_exit:
  rts                 ; 6 cycles                              (e)
