add_morse_demo:
  jsr buffer_initialize

  lda #<write_morse_buffer
  ldx #>write_morse_buffer
  jsr initialize_additional_process

  lda #<send_morse_message
  ldx #>send_morse_message
  jsr initialize_additional_process

  rts


write_morse_buffer:
  lda #DISPLAY_LAST_LINE + 5     ; Console position
  ldx #DISPLAY_WIDTH - 10        ; Console length
  jsr console_initialize
write_morse_buffer_repeat:
  jsr buffer_read
  jsr console_print_character
  jsr console_show
  bra write_morse_buffer_repeat


morse_message:
  .asciiz 'Test 123, HELLO WORLD THIS IS A COMPUTER BUILT BY PHIL'

morse_callback = buffer_write

send_morse_message:
  lda #<morse_callback
  ldx #>morse_callback
  jsr initialize_morse

repeat_morse_message:
  lda #<morse_message
  ldx #>morse_message
  jsr send_morse_string

  lda #' '
  jsr write_to_buffer_with_delay
  lda #'.'
  jsr write_to_buffer_with_delay
  jsr write_to_buffer_with_delay
  jsr write_to_buffer_with_delay
  lda #' '

  bra repeat_morse_message


; On entry A = the character to send
write_to_buffer_with_delay:
  pha
  jsr buffer_write
  lda #<500
  ldx #>500
  jsr sleep_milliseconds
  pla
  rts

