; On entry A = delay in 10 thousandths of a second
; On exit  A is preserved
;          X, Y are not preserved
delay_10_thousandths:
  tax
outer_delay:       ; looking to have 100 cycles per iteration
  beq delay_done   ; 2 cycles
  
  ; 9 cycles outside of inner loop (excluding extra delay)
  ; need total of 100 - 9 = 91 extra cycles 
  ; 91 / 5 = 18.2 iterations
  ; 18 iterations = 17 * 5 + 4 = 89 cycles
  ; extra delay = 91 - 89 = 2 cycles
  nop              ; 2 cycles (extra delay)
  ldy #18          ; 2 cycles
inner_delay:       ; Per iteration: 5 cycles; 4 on last
  dey              ; 2 cycles
  bne inner_delay  ; 3 cycles

  dex              ; 2 cycles
  jmp outer_delay  ; 3 cycles
delay_done:
  rts
