; On entry A = delay in 10 thousandths of a second
; On exit  A, X and Y are preserved
delay_10_thousandths: ; 6 cycles* (assuming jsr to the routine)
  cmp #0              ; 2 cycles*
  beq delay_exit      ; 2 cycles* (if branch does not succeed)
  phx                 ; 3 cycles*
  phy                 ; 3 cycles*
  tax                 ; 2 cycles*
  ; Delay goes here to make the balance of the first 100 cycles
  ; The outer delay below takes 100 cycles per iteration and 99 on the last
  ; 34 cycles outside of the inner loop (*); need 99 - 34 = 65 extra
  ; 65 / 5 = 13 iterations
  ; 12 iterations = 11 * 5 + 4 = 59 cycles
  ; extra delay = 65 - 59 = 6 cycles
  nop                 ; 2 cycles (extra delay)
  nop                 ; 2 cycles (extra delay)
  nop                 ; 2 cycles (extra delay)
  ldy #12             ; 2 cycles*
inner_delay_0:        ; Per iteration: 5 cycles; 4 on last
  dey                 ; 2 cycles
  bne inner_delay_0   ; 3 cycles or 2 if branch not taken

outer_delay:          ; looking to have 100 cycles per iteration
  ; 7 cycles outside of inner loop (+) (excluding extra delay)
  ; need total of 100 - 7 = 93 extra cycles 
  ; 93 / 5 = 18.6 iterations
  ; 18 iterations = 17 * 5 + 4 = 89 cycles
  ; extra delay = 93 - 89 = 4 cycles
  nop                 ; 2 cycles (extra delay)
  nop                 ; 2 cycles (extra delay)
  ldy #18             ; 2 cycles+
inner_delay:          ; Per iteration: 5 cycles; 4 on last
  dey                 ; 2 cycles
  bne inner_delay     ; 3 cycles or 2 if branch not taken

  dex                 ; 2 cycles+
  bne outer_delay     ; 3 cycles+ (2 cycles on last iteration)

  ply                 ; 4 cycles*
  plx                 ; 4 cycles*
delay_exit:
  rts                 ; 6 cycles*
