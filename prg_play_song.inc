; Play a song
; Requires PLAY_SONG_PARAM 2 byte location for temporary storage of song location

play_song:
  sta PLAY_SONG_PARAM
replay_song:
  phx
  stx PLAY_SONG_PARAM + 1
  ldy #0                   ; Music position counter
song_loop:
  lda (PLAY_SONG_PARAM),Y
  cmp #NOTE_IDX_NULL
  beq done_with_song
  cmp #NOTE_IDX_REST
  beq song_rest
  jsr start_note
  bra song_delay
song_rest:
  jsr stop_note
song_delay:
  iny
  lda (PLAY_SONG_PARAM),Y
  asl
  phy
  tay
  lda durations,Y
  ldx durations + 1,Y
  ply
  jsr sleep_milliseconds
  iny
  bne song_loop
  ; increment the song param high byte
  inc PLAY_SONG_PARAM + 1
  bra song_loop
done_with_song:
  jsr stop_note
  lda #<1000
  ldx #>1000
  jsr sleep_milliseconds
  plx
  bra replay_song 
