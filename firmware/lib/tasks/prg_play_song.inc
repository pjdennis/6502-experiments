PLAY_SONG_PARAM                = $0000 ; 2 bytes
PLAY_SONG_CURRENT_NOTE_IDX     = $0002 ; 1 byte
PLAY_SONG_CURRENT_DURATION_IDX = $0003 ; 1 byte
PLAY_SONG_DELAY                = $0004 ; 2 bytes


; Play a song
play_song:
  sta PLAY_SONG_PARAM
.replay_song:
  phx
  stx PLAY_SONG_PARAM + 1
  ldy #0                   ; Music position counter
.song_loop:
  lda (PLAY_SONG_PARAM),Y
  cmp #NOTE_IDX_NULL
  beq .done_with_song
  sta PLAY_SONG_CURRENT_NOTE_IDX
  iny
  lda (PLAY_SONG_PARAM),Y
  sta PLAY_SONG_CURRENT_DURATION_IDX
  iny
  bne .moved_next
  inc PLAY_SONG_PARAM + 1
.moved_next:
  ; Store current duration
  lda PLAY_SONG_CURRENT_DURATION_IDX
  asl
  tax
  lda durations,X
  sta PLAY_SONG_DELAY
  lda durations + 1,X
  sta PLAY_SONG_DELAY + 1
  ; Evaluate how to handle current note
  lda PLAY_SONG_CURRENT_NOTE_IDX
  cmp #NOTE_IDX_REST
  beq .song_rest
  cmp (PLAY_SONG_PARAM),Y ; compare with next note
  beq .song_shortened_note
; regular note
  jsr start_note
  jsr .song_delay
  bra .song_loop
.song_rest:
  jsr stop_note
  jsr .song_delay
  bra .song_loop
.song_shortened_note:
  ; play shortened note
  jsr start_note
  sec
  lda PLAY_SONG_DELAY
  sbc #<DURATION_INTER_NOTE
  sta PLAY_SONG_DELAY
  lda PLAY_SONG_DELAY + 1
  sbc #>DURATION_INTER_NOTE
  sta PLAY_SONG_DELAY + 1
  jsr .song_delay
  jsr stop_note
  ; short gap
  lda #<DURATION_INTER_NOTE
  sta PLAY_SONG_DELAY
  lda #>DURATION_INTER_NOTE
  sta PLAY_SONG_DELAY + 1
  jsr .song_delay
  bra .song_loop
.done_with_song:
  jsr stop_note
  lda #<1000
  ldx #>1000
  jsr sleep_milliseconds
  plx
  bra .replay_song

.song_delay:
  lda PLAY_SONG_DELAY
  ldx PLAY_SONG_DELAY + 1
  jsr sleep_milliseconds
  rts
