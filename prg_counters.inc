; Requirements
; BUSY_COUNTER            - 2 byte private memory location used for storing the counter value
; BUSY_COUNTER_INCREMENT  - 2 byte private memory location used for storing increment value
; BUSY_COUNTER_DELTA      - Value used to add or subtract from counter

; Busy loop incrementing and displaying counter
run_counter_top_left:
  lda #BUSY_COUNTER_DELTA
  ldx #(DISPLAY_FIRST_LINE + 0)
  bra run_counter

; Busy loop incrementing and displaying counter
run_counter_top_right:
  lda #(-BUSY_COUNTER_DELTA)
  ldx #(DISPLAY_FIRST_LINE + 12)
  bra run_counter

; Busy loop incrementing and displaying counter
run_counter_bottom_left:
  lda #(-BUSY_COUNTER_DELTA)
  ldx #(DISPLAY_SECOND_LINE + 0)
  bra run_counter

; Busy loop incrementing and displaying counter
run_counter_bottom_right:
  lda #BUSY_COUNTER_DELTA
  ldx #(DISPLAY_SECOND_LINE + 12)
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
  jsr convert_to_hex
  jsr display_character
  txa
  jsr display_character

  lda BUSY_COUNTER
  jsr convert_to_hex
  jsr display_character
  txa
  jsr display_character

  jsr unlock_screen

  ; Add busy counter delta
  lda BUSY_COUNTER
  clc
  adc BUSY_COUNTER_INCREMENT
  sta BUSY_COUNTER
  lda BUSY_COUNTER + 1
  adc BUSY_COUNTER_INCREMENT + 1
  sta BUSY_COUNTER + 1

  lda #<100
  ldx #>100
  jsr sleep_milliseconds

  bra run_counter_repeat

