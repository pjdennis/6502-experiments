add_console_demo:
  jsr buffer_initialize

  lda #<console_write_buffer
  ldx #>console_write_buffer
  jsr initialize_additional_process

  lda #<console_demo_2
  ldx #>console_demo_2
  jsr initialize_additional_process

  rts


console_message: .asciiz 'Hello, World! This is a long scrolling message. Phil X Angel :) ...... '

console_demo_2:
console_demo_2_repeat:
  ldy #0
console_demo_2_loop:
  lda console_message, Y
  beq console_demo_2_repeat
  jsr buffer_write
  lda #<200
  ldx #>200
  jsr sleep_milliseconds
  iny
  bra console_demo_2_loop

console_demo:
  lda #(DISPLAY_SECOND_LINE + 5) ; Console position
  ldx #6                         ; Console length
  jsr console_initialize
console_demo_repeat:
  ldy #0
console_demo_loop:
  lda console_message, Y
  beq console_demo_repeat
  jsr console_print_character
  jsr console_show
  lda #<180
  ldx #>180
  jsr sleep_milliseconds
  iny
  bra console_demo_loop


console_write_buffer:
  lda #(DISPLAY_SECOND_LINE + 5) ; Console position
  ldx #6                         ; Console length
  jsr console_initialize
console_write_buffer_repeat:
  jsr buffer_read
  jsr console_print_character
  jsr console_show
  bra console_write_buffer_repeat


