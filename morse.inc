MORSE_TIME_UNIT         = 150 ; Milliseconds
MORSE_DELAY_PENDING     = 1
MORSE_DELAY_NOT_PENDING = 0

MORSE_STRING_PARAM       = $0000 ; 2 bytes
MORSE_CHARACTER_CALLBACK = $0002 ; 2 bytes

; On entry A = low byte of callback address
;          X = high byte of callback address
initialize_morse:
  sta MORSE_CHARACTER_CALLBACK
  stx MORSE_CHARACTER_CALLBACK + 1
  rts


; On entry A = low byte of address
;          X = high byte of address
; On exit  Y is preserved
;          A, X are not preserved
send_morse_string:
  phy
  sta MORSE_STRING_PARAM
  stx MORSE_STRING_PARAM + 1
  ldx #MORSE_DELAY_NOT_PENDING      ; No prior letters requiring a gap
  ldy #0
morse_string_loop:
  lda (MORSE_STRING_PARAM),Y
  beq morse_string_done
  cmp #' '
  beq morse_string_space
  ; non-space
  cpx #MORSE_DELAY_PENDING
  bne morse_string_send_letter
  pha
  lda #3                            ; Delay between letters
  jsr morse_delay
  pla
morse_string_send_letter:
  jsr morse_invoke_callback 
  jsr send_morse_letter
  ldx #MORSE_DELAY_PENDING
  bra morse_string_letter_done
morse_string_space:
  cpx #MORSE_DELAY_PENDING
  bne morse_string_letter_done
  jsr morse_invoke_callback 
  lda #7                            ; Inter-word delay
  jsr morse_delay
  ldx #MORSE_DELAY_NOT_PENDING
morse_string_letter_done:
  iny
  bra morse_string_loop
morse_string_done:
  ply
  rts 


; On entry A = the ASCII letter to send - 'A' through 'Z', '0 through 9' or ' '
; On exit X, Y are preserved
;         A is not preserved
send_morse_letter:
  phx
  phy
  sec
  sbc #'A'
  tax
  lda morse_letters, X
  tay
  and #%00000111        ; Mask the part count
  tax
  tya
morse_send_loop:        ; Loop counter in X
  asl
  tay
  bcs morse_dot
  ; morse_dash
  lda #3
  bra morse_send
morse_dot:
  lda #1  
morse_send:
  jsr morse_send_part   ; Length in A
  dex
  beq morse_letter_done
  lda #1
  jsr morse_delay       ; Length in A
  tya
  bra morse_send_loop
morse_letter_done:
  ply
  plx
  rts


; On entry A = units of delay
; On exit  X, Y are preserved
;          A is not preserved
morse_send_part:
  pha                     ; Turn on LED
  lda #MORSE_LED
  tsb PORTA
  pla

  jsr morse_delay         ; Delay for specified units

  lda #MORSE_LED          ; Turn off LED
  trb PORTA

  rts


; On entry A = units of delay
morse_delay:
  phx
  phy

  tay
morse_delay_loop:
  lda #<MORSE_TIME_UNIT
  ldx #>MORSE_TIME_UNIT
  jsr sleep_milliseconds
  dey
  bne morse_delay_loop

  ply
  plx
  rts


; On entry A contains the character to publish
; On exit  A, X, Y are preserved
morse_invoke_callback:
  phx
  ldx MORSE_CHARACTER_CALLBACK
  bne morse_has_callback
  ldx MORSE_CHARACTER_CALLBACK + 1
  beq morse_callback_exit
morse_has_callback:
  pha
  phy
  jsr morse_invoke_callback_nosave
  ply
  pla
morse_callback_exit:
  plx
  rts

morse_invoke_callback_nosave:
  jmp (MORSE_CHARACTER_CALLBACK)


morse_letters:
  .byte %10000010 ; A ._
  .byte %01110100 ; B _...
  .byte %01010100 ; C _._.
  .byte %01100011 ; D _..
  .byte %10000001 ; E .
  .byte %11010100 ; F .._.
  .byte %00100011 ; G _ _.
  .byte %11110100 ; H ....
  .byte %11000010 ; I ..
  .byte %10000100 ; J ._ _ _
  .byte %01000011 ; K _._
  .byte %10110100 ; L ._..
  .byte %00000010 ; M _ _
  .byte %01000010 ; N _.
  .byte %00000011 ; O _ _ _
  .byte %10010100 ; P ._ _.
  .byte %00100100 ; Q _ _._
  .byte %10100011 ; R ._.
  .byte %11100011 ; S ...
  .byte %00000001 ; T _
  .byte %11000011 ; U .._
  .byte %11100100 ; V ..._
  .byte %10000011 ; W ._ _
  .byte %01100100 ; X _.._
  .byte %01000100 ; Y _._ _
  .byte %00110100 ; Z _ _..

morse_numbers:
  .byte %00000101 ; 0 _ _ _ _ _
  .byte %10000101 ; 1 ._ _ _ _
  .byte %11000101 ; 2 .._ _ _
  .byte %11100101 ; 3 ..._ _
  .byte %11110101 ; 4 ...._
  .byte %11111101 ; 5 .....
  .byte %01111101 ; 6 _....
  .byte %00111101 ; 7 _ _...
  .byte %00011101 ; 8 _ _ _..
  .byte %00001101 ; 9 _ _ _ _.

