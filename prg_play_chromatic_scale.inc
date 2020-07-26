play_chromatic_scale:
  ldy #NOTE_IDX_C4
scale_loop_up:
  tya
  jsr start_note
  
  lda #<500
  ldx #>500
  jsr sleep_milliseconds

  iny
  cpy #(NOTE_IDX_C5 + 1)
  bne scale_loop_up

  ldy #NOTE_IDX_B4
scale_loop_down:
  tya
  jsr start_note

  lda #<500
  ldx #>500
  jsr sleep_milliseconds

  dey
  cpy #(NOTE_IDX_C4 - 1)
  bne scale_loop_down

  jsr stop_note
  
  lda #<1500
  ldx #>1500
  jsr sleep_milliseconds

  bra play_chromatic_scale
