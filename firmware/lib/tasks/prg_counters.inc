BUSY_COUNTER_DELTA = 1         ; Value to add/subtract from counter on each cycle

BUSY_COUNTER           = $0000 ; 2 bytes
BUSY_COUNTER_INCREMENT = $0002 ; 2 bytes
BUSY_COUNTER_LOCATION  = $0004

; Busy loops incrementing and displaying counter

run_counter_top_left:
  lda #BUSY_COUNTER_DELTA
  ldx #(DISPLAY_FIRST_LINE + 0)
  bra run_counter

run_counter_top_right:
  lda #(-BUSY_COUNTER_DELTA)
  ldx #(DISPLAY_FIRST_LINE + DISPLAY_WIDTH - 4)
  bra run_counter

run_counter_bottom_left:
  lda #(-BUSY_COUNTER_DELTA)
  ldx #(DISPLAY_LAST_LINE + 0)
  bra run_counter

run_counter_bottom_right:
  lda #BUSY_COUNTER_DELTA
  ldx #(DISPLAY_LAST_LINE + DISPLAY_WIDTH - 4)
  bra run_counter

run_counter:
  stx BUSY_COUNTER_LOCATION
  sta BUSY_COUNTER_INCREMENT
  ldy #0
  tax
  bpl store_counter_increment_high_byte
  dey
store_counter_increment_high_byte:
  sty BUSY_COUNTER_INCREMENT + 1

  lda #0
  sta BUSY_COUNTER
  sta BUSY_COUNTER + 1
run_counter_repeat:
  jsr lock_screen

  lda BUSY_COUNTER_LOCATION
  jsr move_cursor

  lda BUSY_COUNTER + 1
  jsr display_hex

  lda BUSY_COUNTER
  jsr display_hex

  jsr unlock_screen

  ; Add busy counter delta
  clc
  lda BUSY_COUNTER
  adc BUSY_COUNTER_INCREMENT
  sta BUSY_COUNTER
  lda BUSY_COUNTER + 1
  adc BUSY_COUNTER_INCREMENT + 1
  sta BUSY_COUNTER + 1

  lda #<100
  ldx #>100
  jsr sleep_milliseconds

  bra run_counter_repeat

