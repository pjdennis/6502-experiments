play_ditty:
  lda #<ditty
  ldx #>ditty
  jmp play_song ; tail call

ditty:
  .byte NOTE_IDX_C4,   DURATION_IDX_SEMIBREVE 

  .byte NOTE_IDX_E4,   DURATION_IDX_SEMIBREVE

  .byte NOTE_IDX_G4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_REST, DURATION_IDX_QUAVER
  .byte NOTE_IDX_REST, DURATION_IDX_QUAVER
  .byte NOTE_IDX_F4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_E4,   DURATION_IDX_CROTCHET
  .byte NOTE_IDX_D4,   DURATION_IDX_CROTCHET

  .byte NOTE_IDX_C4,   DURATION_IDX_SEMIBREVE

  .byte NOTE_IDX_A4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_G4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_A4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_G4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_A4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_G4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_F4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_E4,   DURATION_IDX_QUAVER

  .byte NOTE_IDX_G4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_F4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_G4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_F4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_G4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_F4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_E4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_D4,   DURATION_IDX_QUAVER

  .byte NOTE_IDX_E4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_D4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_E4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_F4,   DURATION_IDX_QUAVER
  .byte NOTE_IDX_E4,   DURATION_IDX_CROTCHET
  .byte NOTE_IDX_D4,   DURATION_IDX_CROTCHET

  .byte NOTE_IDX_C4,   DURATION_IDX_SEMIBREVE

  ; Outro
  ;.byte NOTE_IDX_REST, DURATION_IDX_SEMIBREVE
  ;.byte NOTE_IDX_C4,   DURATION_IDX_SEMIBREVE
  ;.byte NOTE_IDX_D4,   DURATION_IDX_SEMIBREVE
  ;.byte NOTE_IDX_E4,   DURATION_IDX_SEMIBREVE
  ;.byte NOTE_IDX_G4,   DURATION_IDX_SEMIBREVE
  ;.byte NOTE_IDX_G4,   DURATION_IDX_SEMIBREVE

  .byte NOTE_IDX_NULL


