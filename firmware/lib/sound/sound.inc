; On entry A = index of note
; On exit  X, Y are preserved
;          A is not preserved
start_note:
  phy
  asl
  tay
  lda NOTE_PLAYING
  beq first_note
  ; not the first note
  lda notes,Y
  sta T1LL
  lda notes + 1,Y
  sta T1LH
  bra start_note_done
first_note:
  lda #ACR_T1_CONT_SQWAVE  ; Enable timer 1 continuous square wave
  sta ACR

  lda notes,Y
  sta T1CL
  lda notes + 1,Y
  sta T1CH                 ; Starts the timer
  lda #1
  sta NOTE_PLAYING
start_note_done:
  ply
  rts


stop_note:
  lda NOTE_PLAYING
  beq note_stopped
  lda #0
  sta ACR
  STA T1CL
  STA T1CH
  sta NOTE_PLAYING
note_stopped:
  rts

